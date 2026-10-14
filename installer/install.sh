#!/usr/bin/env bash
set -euo pipefail

config_path="${1:?install configuration path is required}"
source_root="/run/source"
target_root="/target"

fail() {
  echo "" >&2
  echo "==============================================================" >&2
  echo ">>> [INSTALLATION FAILED] $*" >&2
  echo "==============================================================" >&2
  sync
  exit 1
}

normalize_guid() {
  tr -d '[:space:]-{}' | tr '[:lower:]' '[:upper:]'
}

json_string() {
  jq -er "$1" "${config_path}"
}

partition_device() {
  local raw="$1"
  local exp_norm
  exp_norm="$(printf '%s' "${raw}" | normalize_guid)"
  [[ -z "${exp_norm}" ]] && return 1

  local dev=""
  for _ in {1..10}; do
    # 1. Match via findfs
    local lower_raw
    lower_raw="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"
    dev="$(findfs PARTUUID="${lower_raw}" 2>/dev/null || findfs PARTUUID="${raw}" 2>/dev/null || true)"
    if [[ -b "${dev}" ]]; then
      printf '%s\n' "${dev}"
      return 0
    fi

    # 2. Match via lsblk -lno PATH,PARTUUID (list format, no tree artifacts)
    local lsblk_parts
    if lsblk_parts="$(lsblk -lno PATH,PARTUUID 2>/dev/null)"; then
      while read -r path partuuid; do
        [[ -z "${path}" || -z "${partuuid}" ]] && continue
        local p_norm
        p_norm="$(printf '%s' "${partuuid}" | normalize_guid)"
        if [[ "${p_norm}" == "${exp_norm}" && -b "${path}" ]]; then
          printf '%s\n' "${path}"
          return 0
        fi
      done <<< "${lsblk_parts}"
    fi

    # 3. Match via blkid
    dev="$(blkid -t "PARTUUID=${lower_raw}" -o device 2>/dev/null | head -n 1 || true)"
    [[ -z "${dev}" ]] && dev="$(blkid -t "PARTUUID=${raw}" -o device 2>/dev/null | head -n 1 || true)"
    if [[ -b "${dev}" ]]; then
      printf '%s\n' "${dev}"
      return 0
    fi

    # 4. Direct device candidate lookup if target_disk is known
    if [[ -n "${target_disk:-}" && -n "${number:-}" ]]; then
      local candidate
      case "${target_disk}" in
        /dev/nvme*|/dev/mmcblk*) candidate="${target_disk}p${number}" ;;
        *) candidate="${target_disk}${number}" ;;
      esac
      if [[ -b "${candidate}" ]]; then
        local candidate_uuid
        candidate_uuid="$(lsblk -dno PARTUUID "${candidate}" 2>/dev/null | normalize_guid || true)"
        if [[ "${candidate_uuid}" == "${exp_norm}" ]]; then
          printf '%s\n' "${candidate}"
          return 0
        fi
      fi
    fi

    mdev -s 2>/dev/null || true
    sleep 1
  done

  printf '%s\n' "${dev}"
}

find_target_disk() {
  local expected="$1"
  local exp_norm
  exp_norm="$(printf '%s' "${expected}" | normalize_guid)"
  [[ -z "${exp_norm}" ]] && return 1

  # 1. Match via lsblk disk PTUUID (list format)
  local lsblk_out
  if lsblk_out="$(lsblk -lno PATH,PTUUID 2>/dev/null)"; then
    while read -r path ptuuid; do
      [[ -z "${path}" || -z "${ptuuid}" ]] && continue
      local p_norm
      p_norm="$(printf '%s' "${ptuuid}" | normalize_guid)"
      if [[ "${p_norm}" == "${exp_norm}" && -b "${path}" ]]; then
        printf '%s\n' "${path}"
        return 0
      fi
    done <<< "${lsblk_out}"
  fi

  # 2. Match via sgdisk on candidate whole disks
  for dev in /dev/vd[a-z] /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/mmcblk[0-9] /dev/xvd[a-z]; do
    [[ -b "${dev}" ]] || continue
    local sg_raw
    sg_raw="$(sgdisk --print "${dev}" 2>/dev/null || true)"
    local sg_guid
    sg_guid="$(grep -i 'Disk identifier' <<< "${sg_raw}" | awk '{print $NF}' | normalize_guid || true)"
    if [[ -n "${sg_guid}" && "${sg_guid}" == "${exp_norm}" ]]; then
      printf '%s\n' "${dev}"
      return 0
    fi
  done

  # 3. Fallback: locate disk via existing EFI partition PARTUUID
  local efi_guid
  efi_guid="$(jq -r '.partitions[] | select(.isExisting == true and .mountPoint == "/boot/efi") | .guid' "${config_path}" 2>/dev/null | head -n 1 || true)"
  if [[ -n "${efi_guid}" ]]; then
    local efi_dev
    efi_dev="$(partition_device "${efi_guid}")"
    if [[ -b "${efi_dev}" ]]; then
      local parent_disk
      parent_disk="$(lsblk -no PKNAME "${efi_dev}" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ -n "${parent_disk}" && -b "/dev/${parent_disk}" ]]; then
        printf '/dev/%s\n' "${parent_disk}"
        return 0
      fi
    fi
  fi

  return 1
}

ln -s /proc/self/fd /dev/fd 2>/dev/null || true
ln -s /proc/self/fd/0 /dev/stdin 2>/dev/null || true
ln -s /proc/self/fd/1 /dev/stdout 2>/dev/null || true
ln -s /proc/self/fd/2 /dev/stderr 2>/dev/null || true

mount -o remount,rw "${source_root}" 2>/dev/null || mount -t ntfs3 -o remount,rw,force "${source_root}" 2>/dev/null || true
mkdir -p "${source_root}/.myinstaller" 2>/dev/null || true
log_file="/tmp/install.log"
if touch "${source_root}/.myinstaller/install.log" 2>/dev/null; then
  log_file="${source_root}/.myinstaller/install.log"
fi

echo ""
echo "=============================================================="
echo "    LinuxInstallerForWindows (Stage 2: Installation)          "
echo "=============================================================="
echo ">>> Initializing installation pipeline..."

[[ -f "${config_path}" ]] || fail "install.json is missing"
[[ "$(jq -r '.schemaVersion' "${config_path}")" == "1" ]] || fail "unsupported install configuration"

echo ">>> [1/6] Scanning and validating storage layout..."
target_disk_guid="$(json_string '.targetDiskGuid')"
target_disk="$(find_target_disk "${target_disk_guid}" || true)"
[[ -b "${target_disk}" ]] || fail "target GPT disk ${target_disk_guid} was not found"
echo ">>> Target storage device: ${target_disk}"

sector_size="$(blockdev --getss "${target_disk}")"
[[ "${sector_size}" =~ ^[0-9]+$ && "${sector_size}" -gt 0 ]] || fail "logical sector size is invalid"

echo ">>> [2/6] Partitioning disk and registering GPT GUIDs..."
jq -c '.partitions[] | select(.isExisting == false)' "${config_path}" > /tmp/new_partitions.json
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

  echo ">>> Creating partition ${number} [${start_sector} - ${end_sector}] GUID=${guid}..."
  sgdisk --delete="${number}" "${target_disk}" 2>/dev/null || true
  sgdisk \
    --new="${number}:${start_sector}:${end_sector}" \
    --typecode="${number}:8300" \
    --partition-guid="${number}:${guid}" \
    --change-name="${number}:${name}" \
    "${target_disk}" || fail "could not create partition ${number}"
done < /tmp/new_partitions.json

partprobe "${target_disk}" 2>/dev/null || true
partx -u "${target_disk}" 2>/dev/null || true
partx -a "${target_disk}" 2>/dev/null || true
blockdev --rereadpt "${target_disk}" 2>/dev/null || true
mdev -s 2>/dev/null || true
udevadm settle 2>/dev/null || true
sleep 2

echo ">>> [3/6] Formatting target filesystems..."
while IFS= read -r partition; do
  guid="$(jq -r '.guid' <<<"${partition}")"
  file_system="$(jq -r '.fileSystem' <<<"${partition}")"
  number="$(jq -r '.number' <<<"${partition}")"
  device="$(partition_device "${guid}" || true)"
  [[ -b "${device}" ]] || fail "new partition ${guid} was not discovered"

  echo ">>> Formatting ${device} as ${file_system}..."
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
done < /tmp/new_partitions.json

root_partition="$(jq -cer '.partitions[] | select(.mountPoint == "/")' "${config_path}")"
root_guid="$(jq -r '.guid' <<<"${root_partition}")"
root_file_system="$(jq -r '.fileSystem' <<<"${root_partition}")"
root_device="$(partition_device "${root_guid}" || true)"
[[ -b "${root_device}" ]] || fail "root partition was not found"

mkdir -p "${target_root}"
mount "${root_device}" "${target_root}" || fail "root partition could not be mounted"

jq -c '.partitions[] | select(.mountPoint != "" and .mountPoint != "/")' "${config_path}" | sort > /tmp/mount_partitions.json
while IFS= read -r partition; do
  mount_point="$(jq -r '.mountPoint' <<<"${partition}")"
  guid="$(jq -r '.guid' <<<"${partition}")"
  device="$(partition_device "${guid}" || true)"
  [[ -b "${device}" ]] || fail "partition for ${mount_point} was not found"
  mkdir -p "${target_root}${mount_point}"
  mount "${device}" "${target_root}${mount_point}" || fail "${mount_point} could not be mounted"
done < /tmp/mount_partitions.json

echo ">>> [4/6] Extracting root filesystem payload..."
rootfs_file="$(json_string '.rootfsFileName')"
rootfs_path="${source_root}/.myinstaller/${rootfs_file}"
[[ -f "${rootfs_path}" ]] || fail "root filesystem archive is missing"
zstd -dc "${rootfs_path}" | tar --numeric-owner -xpf - -C "${target_root}"

mkdir -p "${target_root}/boot" "${target_root}/boot/grub" "${target_root}/etc"
cp "${source_root}/.myinstaller/installer.vmlinuz" "${target_root}/boot/vmlinuz-linux-installer"
cp "${source_root}/.myinstaller/installer.initrd" "${target_root}/boot/initramfs-linux-installer.img"
chmod 0644 "${target_root}/boot/vmlinuz-linux-installer" "${target_root}/boot/initramfs-linux-installer.img"

: > "${target_root}/etc/fstab"
jq -c '.partitions[] | select(.mountPoint != "")' "${config_path}" > /tmp/fstab_partitions.json
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
  fstab_options="defaults"
  [[ "${mount_point}" == "/" ]] || fstab_options="defaults,nofail"
  printf 'UUID=%s %s %s %s 0 %s\n' "${uuid}" "${mount_point}" "${fstab_type}" "${fstab_options}" "${pass_number}" >> "${target_root}/etc/fstab"
done < /tmp/fstab_partitions.json

echo ">>> [5/6] Configuring user accounts, locale, and network identity..."
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
password_hash="$(jq -r '.user.passwordHash // empty' "${config_path}")"
password_base64="$(jq -r '.user.passwordBase64 // empty' "${config_path}")"
auto_login="$(jq -r '.user.autoLogin' "${config_path}")"

if ! chroot "${target_root}" id -u "${username}" >/dev/null 2>&1; then
  chroot "${target_root}" useradd -m -c "${full_name}" -s /bin/bash "${username}"
fi

if chroot "${target_root}" getent group sudo >/dev/null 2>&1; then
  chroot "${target_root}" usermod -aG sudo "${username}"
elif chroot "${target_root}" getent group wheel >/dev/null 2>&1; then
  chroot "${target_root}" usermod -aG wheel "${username}"
fi

if [[ -n "${password_hash}" ]]; then
  echo "${username}:${password_hash}" | chroot "${target_root}" chpasswd -e
elif [[ -n "${password_base64}" ]]; then
  password_file="$(mktemp)"
  printf '%s' "${password_base64}" | base64 -d > "${password_file}"
  {
    printf '%s:' "${username}"
    cat "${password_file}"
    printf '\n'
  } | chroot "${target_root}" chpasswd
  shred -u "${password_file}" 2>/dev/null || rm -f "${password_file}"
fi

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

echo ">>> [6/6] Probing operating systems and generating bootloader configuration..."
root_uuid="$(blkid -s UUID -o value "${root_device}")"
distro_name="$(json_string '.distroName')"
/opt/linux-installer/post-setup.sh "${target_root}" "${distro_name}" "${root_uuid}" "${root_file_system}"

result_path="${source_root}/.myinstaller/install-result.json"
jq 'del(.user.passwordBase64, .user.passwordHash) | .status = "staged-for-first-boot"' "${config_path}" > "${result_path}" 2>/dev/null || true
rm -f "${config_path}" "${source_root}/.myinstaller/stage2.cfg" 2>/dev/null || true

mkdir -p "${target_root}/var/log" 2>/dev/null || true
cp "${log_file}" "${target_root}/var/log/lifw-install.log" 2>/dev/null || true
if [[ "${log_file}" != "${source_root}/.myinstaller/install.log" ]]; then
  cp "${log_file}" "${source_root}/.myinstaller/install.log" 2>/dev/null || true
fi

sync
echo ""
echo "=============================================================="
echo ">>> Installation completed successfully!                     "
echo ">>> Rebooting into ${distro_name} in 3 seconds...            "
echo "=============================================================="
sleep 3
reboot -f
