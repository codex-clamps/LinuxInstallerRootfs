#!/usr/bin/env bash
set -euo pipefail

target_root="${1:?target root is required}"
distro_name="${2:?distribution name is required}"
root_uuid="${3:?root filesystem UUID is required}"
root_file_system="${4:?root filesystem type is required}"

efi_directory="${target_root}/boot/efi/EFI/LinuxInstaller"
root_grub_directory="${target_root}/boot/grub"
mkdir -p "${efi_directory}" "${root_grub_directory}"

cat > "${root_grub_directory}/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "${distro_name}" {
    search --no-floppy --fs-uuid --set=linux_root ${root_uuid}
    linux (\$linux_root)/boot/vmlinuz-linux-installer root=UUID=${root_uuid} rootfstype=${root_file_system} rw
    initrd (\$linux_root)/boot/initramfs-linux-installer.img
}

menuentry "Windows Boot Manager" {
    search --no-floppy --file --set=windows_esp /EFI/Microsoft/Boot/bootmgfw.efi
    chainloader (\$windows_esp)/EFI/Microsoft/Boot/bootmgfw.efi
}
EOF

cat > "${efi_directory}/grub.cfg" <<EOF
search --no-floppy --fs-uuid --set=linux_root ${root_uuid}
set root=\$linux_root
configfile (\$linux_root)/boot/grub/grub.cfg
EOF
