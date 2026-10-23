#!/usr/bin/env bash
set -euo pipefail

target_root="${1:?target root is required}"
distro_name="${2:?distribution name is required}"
root_uuid="${3:?root filesystem UUID is required}"
root_file_system="${4:?root filesystem type is required}"
kernel_file="${5:-vmlinuz-linux-installer}"
initrd_file="${6:-initramfs-linux-installer.img}"

echo ">>> Configuring bootloader and probing operating systems..."
efi_directory="${target_root}/boot/efi/EFI/LinuxInstaller"
root_grub_directory="${target_root}/boot/grub"
mkdir -p "${efi_directory}" "${root_grub_directory}"

# 1. Enable os-prober in target /etc/default/grub
if [[ -f "${target_root}/etc/default/grub" ]]; then
  if grep -q "^GRUB_DISABLE_OS_PROBER=" "${target_root}/etc/default/grub"; then
    sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "${target_root}/etc/default/grub"
  else
    echo "GRUB_DISABLE_OS_PROBER=false" >> "${target_root}/etc/default/grub"
  fi
elif [[ -d "${target_root}/etc/default" ]]; then
  echo "GRUB_DISABLE_OS_PROBER=false" >> "${target_root}/etc/default/grub"
fi

# 2. Generate GRUB configuration using target or toolchain grub-mkconfig
grub_generated=false

if chroot "${target_root}" command -v update-grub >/dev/null 2>&1; then
  echo ">>> Running update-grub in target system..."
  chroot "${target_root}" update-grub && grub_generated=true || true
elif chroot "${target_root}" command -v grub-mkconfig >/dev/null 2>&1; then
  echo ">>> Running grub-mkconfig in target system..."
  chroot "${target_root}" grub-mkconfig -o /boot/grub/grub.cfg && grub_generated=true || true
elif chroot "${target_root}" command -v grub2-mkconfig >/dev/null 2>&1; then
  echo ">>> Running grub2-mkconfig in target system (Fedora/RHEL)..."
  chroot "${target_root}" grub2-mkconfig -o /boot/grub2/grub.cfg && grub_generated=true || true
  # Expose the Fedora-style config on the path the UEFI forwarding stub reads
  if [[ "${grub_generated}" == "true" && -s "${target_root}/boot/grub2/grub.cfg" && ! -e "${root_grub_directory}/grub.cfg" ]]; then
    ln -sfn grub2/grub.cfg "${root_grub_directory}/grub.cfg"
  fi
elif command -v grub-mkconfig >/dev/null 2>&1; then
  echo ">>> Running toolchain grub-mkconfig..."
  grub-mkconfig -o "${root_grub_directory}/grub.cfg" && grub_generated=true || true
fi

# 3. If grub.cfg was not generated or does not contain a primary entry, write a solid base config
if [[ "${grub_generated}" != "true" || ! -s "${root_grub_directory}/grub.cfg" ]]; then
  echo ">>> Writing primary GRUB configuration..."
  cat > "${root_grub_directory}/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "${distro_name}" {
    search --no-floppy --fs-uuid --set=linux_root ${root_uuid}
    linux (\$linux_root)/boot/${kernel_file} root=UUID=${root_uuid} rootfstype=${root_file_system} rw
    initrd (\$linux_root)/boot/${initrd_file}
}
EOF
fi

# 4. Guarantee a Windows Boot Manager fallback entry if not already present
if ! grep -q "bootmgfw.efi" "${root_grub_directory}/grub.cfg" 2>/dev/null; then
  echo ">>> Adding Windows Boot Manager chainloader fallback..."
  cat >> "${root_grub_directory}/grub.cfg" <<EOF

menuentry "Windows Boot Manager" {
    search --no-floppy --file --set=windows_esp /EFI/Microsoft/Boot/bootmgfw.efi
    chainloader (\$windows_esp)/EFI/Microsoft/Boot/bootmgfw.efi
}
EOF
fi

# 5. Write Stage 1 forwarding config into ESP
cat > "${efi_directory}/grub.cfg" <<EOF
search --no-floppy --fs-uuid --set=linux_root ${root_uuid}
set root=\$linux_root
configfile (\$linux_root)/boot/grub/grub.cfg
EOF

echo ">>> GRUB configuration successfully generated and verified."
