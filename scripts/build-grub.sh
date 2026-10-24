#!/usr/bin/env bash
set -euo pipefail

output_directory="dist"
embedded_config="$(mktemp)"
trap 'rm -f "${embedded_config}"' EXIT

sudo apt-get update
sudo apt-get install --yes grub-common grub-efi-amd64-bin

mkdir -p "${output_directory}"
cat > "${embedded_config}" <<'GRUBCFG'
# The firmware may lazy-connect storage controllers, leaving non-boot disks
# unenumerated; connect them all before probing for installer payloads
connectefi all

search --no-floppy --file --set=final_esp /EFI/LinuxInstaller/grub.cfg
if [ -n "$final_esp" ]; then
    set root="$final_esp"
    configfile /EFI/LinuxInstaller/grub.cfg
fi

search --no-floppy --file --set=installer_root /.myinstaller/stage2.cfg
if [ -n "$installer_root" ]; then
    set root="$installer_root"
    configfile /.myinstaller/stage2.cfg
fi

echo "LinuxInstallerForWindows configuration was not found."
sleep --interruptible 10
GRUBCFG

grub-mkstandalone \
  --format=x86_64-efi \
  --output="${output_directory}/grubx64.efi" \
  --modules="connectefi part_gpt part_msdos fat ntfs ext2 btrfs normal linux chain configfile search search_fs_file search_fs_uuid search_label echo test sleep" \
  "boot/grub/grub.cfg=${embedded_config}"

sha256sum "${output_directory}/grubx64.efi" | awk '{print $1}' > "${output_directory}/grubx64.efi.sha256"
