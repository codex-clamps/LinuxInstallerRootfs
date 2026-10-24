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

grub_modules="part_gpt part_msdos fat ntfs ext2 btrfs normal linux chain configfile search search_fs_file search_fs_uuid search_label echo test sleep"
# connectefi exists in grub 2.12+; older builds auto-connect at startup instead
if [[ -f "/usr/lib/grub/x86_64-efi/connectefi.mod" ]]; then
  grub_modules="connectefi ${grub_modules}"
fi

grub-mkstandalone \
  --format=x86_64-efi \
  --output="${output_directory}/grubx64.efi" \
  --modules="${grub_modules}" \
  "boot/grub/grub.cfg=${embedded_config}"

sha256sum "${output_directory}/grubx64.efi" | awk '{print $1}' > "${output_directory}/grubx64.efi.sha256"
