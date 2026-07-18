#!/usr/bin/env bash
set -euo pipefail

config_path="${1:?install configuration path is required}"
source_root="/run/source"
target_root="/target"

fail() {
  echo "Installation failed: $*" >&2
  sync
  exit 1
}

normalize_guid() {
  tr '[:lower:]' '[:upper:]' | tr -d '{}'
}

json_string() {
  jq -er "$1" "${config_path}"
}

partition_device() {
  local guid
  guid="$(printf '%s' "$1" | normalize_guid)"
  blkid -t "PARTUUID=${guid}" -o device 2>/dev/null | head -n 1
}

find_target_disk() {
  local expected block name device actual
  expected="$(printf '%s' "$1" | normalize_guid)"
  for block in /sys/class/block/*; do
    [[ -e "${block}/partition" ]] && continue
    name="${block##*/}"
    case "${name}" in
      loop*|ram*|sr*|dm-*) continue ;;
    esac
    device="/dev/${name}"
    [[ -b "${device}" ]] || continue
    actual="$(sgdisk --print "${device}" 2>/dev/null | awk -F': ' '/Disk identifier \(GUID\)/ {print $2; exit}' | normalize_guid || true)"
    if [[ -n "${actual}" && "${actual}" == "${expected}" ]]; then
      printf '%s\n' "${device}"
      return 0
    fi
  done
  return 1
}

mount -o remount,rw "${source_root}" 2>/dev/null || true
mkdir -p "${source_root}/.myinstaller"
exec > >(tee -a "${source_root}/.myinstaller/install.log") 2>&1

[[ -f "${config_path}" ]] || fail "install.json is missing"
[[ "$(jq -r '.schemaVersion' "${config_path}")" == "1" ]] || fail "unsupported install configuration"

target_disk_guid="$(json_string '.targetDiskGuid')"
target_disk="$(find_target_disk "${target_disk_guid}" || true)"
[[ -b "${target_disk}" ]] || fail "target GPT disk ${target_disk_guid} was not found"

sector_size="$(blockdev --getss "${target_disk}")"
[[ "${sector_size}" =~ ^[0-9]+$ && "${sector_size}" -gt 0 ]] || fail "logical sector size is invalid"

while IFS= read -r partition; do
  number="$(jq -r '.number' <<<"${partition}")"
  guid="$(jq -r '.guid' <<<"${partition}")"
  start_bytes="$(jq -r '.startOffsetBytes' <<<"${partition}")"
  size_bytes="$(jq -r '.sizeBytes' <<<"${partition}")"
  name="$(jq -r '.name' <<<"${partition}")"

  (( start_bytes % sector_size == 0 )) || fail "partition ${number} start is not sector aligned"
  (( size_bytes % sector_size == 0 )) || fail "partition ${number} size is not sector aligned"

  start_sector=$((start_bytes / sector_size))
  end_sector=$(((start_bytes + size_bytes) / sector_size - 1))

  sgdisk \
    --new="${number}:${start_sector}:${end_sector}" \
    --typecode="${number}:8300" \
    --partition-guid="${number}:${guid}" \
    --change-name="${number}:${name}" \
    "${target_disk}" || fail "could not create partition ${number}"
done < <(jq -c '.partitions[] | select(.isExisting == false)' "${config_path}")

partprobe "${target_disk}" || true
blockdev --rereadpt "${target_disk}" || true
mdev -s || true
sleep 2

while IFS= read -r partition; do
  guid="$(jq -r '.guid' <<<"${partition}")"
  file_system="$(jq -r '.fileSystem' <<<"${partition}")"
  number="$(jq -r '.number' <<<"${partition}")"
  device="$(partition_device "${guid}" || true)"
  [[ -b "${device}" ]] || fail "new partition ${guid} was not discovered"

  case "${file_system}" in
    ext4)
      mkfs.ext4 -F -L "LIFW${number}" "${device}"
      ;;
    btrfs)
      mkfs.btrfs -f -L "LIFW${number}" "${device}"
      ;;
    *)
      fail "unsupported target filesystem '${file_system}'"
      ;;
  esac
done < <(jq -c '.partitions[] | select(.isExisting == false)' "${config_path}")

root_partition="$(jq -cer '.partitions[] | select(.mountPoint == "/")' "${config_path}")"
root_guid="$(jq -r '.guid' <<<"${root_partition}")"
root_file_system="$(jq -r '.fileSystem' <<<"${root_partition}")"
root_device="$(partition_device "${root_guid}" || true)"
[[ -b "${root_device}" ]] || fail "root partition was not found"

mkdir -p "${target_root}"
mount "${root_device}" "${target_root}" || fail "root partition could not be mounted"

while IFS= read -r partition; do
  mount_point="$(jq -r '.mountPoint' <<<"${partition}")"
  guid="$(jq -r '.guid' <<<"${partition}")"
  device="$(partition_device "${guid}" || true)"
  [[ -b "${device}" ]] || fail "partition for ${mount_point} was not found"
  mkdir -p "${target_root}${mount_point}"
  mount "${device}" "${target_root}${mount_point}" || fail "${mount_point} could not be mounted"
done < <(jq -c '.partitions[] | select(.mountPoint != "" and .mountPoint != "/")' "${config_path}" | sort)

rootfs_file="$(json_string '.rootfsFileName')"
rootfs_path="${source_root}/.myinstaller/${rootfs_file}"
[[ -f "${rootfs_path}" ]] || fail "root filesystem archive is missing"
zstd -dc "${rootfs_path}" | tar --numeric-owner -xpf - -C "${target_root}"

mkdir -p "${target_root}/boot" "${target_root}/boot/grub" "${target_root}/etc"
cp "${source_root}/.myinstaller/installer.vmlinuz" "${target_root}/boot/vmlinuz-linux-installer"
cp "${source_root}/.myinstaller/installer.initrd" "${target_root}/boot/initramfs-linux-installer.img"
chmod 0644 "${target_root}/boot/vmlinuz-linux-installer" "${target_root}/boot/initramfs-linux-installer.img"

: > "${target_root}/etc/fstab"
while IFS= read -r partition; do
  mount_point="$(jq -r '.mountPoint' <<<"${partition}")"
  guid="$(jq -r '.guid' <<<"${partition}")"
  file_system="$(jq -r '.fileSystem' <<<"${partition}")"
  device="$(partition_device "${guid}" || true)"
  uuid="$(blkid -s UUID -o value "${device}")"
  [[ -n "${uuid}" ]] || fail "filesystem UUID for ${mount_point} was not found"
  case "${file_system}" in
    fat32) fstab_type="vfat"; pass_number=0 ;;
    ext4) fstab_type="ext4"; pass_number=1 ;;
    btrfs) fstab_type="btrfs"; pass_number=0 ;;
    *) fail "unsupported fstab filesystem '${file_system}'" ;;
  esac
  [[ "${mount_point}" == "/" ]] || [[ "${pass_number}" == "0" ]] || pass_number=2
  printf 'UUID=%s %s %s defaults 0 %s\n' "${uuid}" "${mount_point}" "${fstab_type}" "${pass_number}" >> "${target_root}/etc/fstab"
done < <(jq -c '.partitions[] | select(.mountPoint != "")' "${config_path}")

hostname="$(json_string '.hostname')"
printf '%s\n' "${hostname}" > "${target_root}/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 %s\n' "${hostname}" > "${target_root}/etc/hosts"

for path in dev proc sys run; do
  mkdir -p "${target_root}/${path}"
  mount --rbind "/${path}" "${target_root}/${path}"
  mount --make-rslave "${target_root}/${path}"
done

username="$(json_string '.user.username')"
full_name="$(json_string '.user.fullName')"
password_base64="$(json_string '.user.passwordBase64')"
auto_login="$(jq -r '.user.autoLogin' "${config_path}")"

if ! chroot "${target_root}" id -u "${username}" >/dev/null 2>&1; then
  chroot "${target_root}" useradd -m -c "${full_name}" -s /bin/bash "${username}"
fi

if chroot "${target_root}" getent group sudo >/dev/null 2>&1; then
  chroot "${target_root}" usermod -aG sudo "${username}"
elif chroot "${target_root}" getent group wheel >/dev/null 2>&1; then
  chroot "${target_root}" usermod -aG wheel "${username}"
fi

password_file="$(mktemp)"
printf '%s' "${password_base64}" | base64 -d > "${password_file}"
{
  printf '%s:' "${username}"
  cat "${password_file}"
  printf '\n'
} | chroot "${target_root}" chpasswd
shred -u "${password_file}" 2>/dev/null || rm -f "${password_file}"

if [[ "${auto_login}" == "true" ]]; then
  mkdir -p "${target_root}/etc/systemd/system/getty@tty1.service.d"
  cat > "${target_root}/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${username} --noclear %I \$TERM
EOF
fi

chroot "${target_root}" systemd-machine-id-setup 2>/dev/null || true
chroot "${target_root}" systemctl enable NetworkManager 2>/dev/null || true
chroot "${target_root}" systemctl enable systemd-networkd 2>/dev/null || true

root_uuid="$(blkid -s UUID -o value "${root_device}")"
distro_name="$(json_string '.distroName')"
/opt/linux-installer/post-setup.sh "${target_root}" "${distro_name}" "${root_uuid}" "${root_file_system}"

result_path="${source_root}/.myinstaller/install-result.json"
jq 'del(.user.passwordBase64) | .status = "staged-for-first-boot"' "${config_path}" > "${result_path}"
rm -f "${config_path}" "${source_root}/.myinstaller/stage2.cfg"

sync
echo "Installation completed. Rebooting into ${distro_name}."
reboot -f
