# Installer toolchains

The toolchain workflow publishes the infrastructure artifacts used by
LinuxInstallerForWindows under the stable toolchains-latest release.

## Required artifacts

- grubx64.efi is a standalone x86_64 UEFI GRUB binary with GPT, FAT, EXT,
  Btrfs, Linux, chainloader, config, and search support.
- filesystem-tools-x86_64.tar.zst is a minimal Alpine userspace containing
  e2fsprogs, btrfs-progs, util-linux, and bash.

## Optional Windows drivers

- winbtrfs-1.9-x64-signed.zip is the official upstream signed WinBtrfs package.
- ext4fsd-0.71-signed-setup.exe is the official upstream signed Ext4Fsd setup.
- winbtrfs-1.9-x64-unsigned.zip is a reproducible development build and must
  not be installed under normal Windows signature enforcement.

The application may download and cache driver packages, but driver installation
must always require explicit user confirmation. Ext4Fsd has documented feature
limitations and must not be treated as universally compatible with modern EXT4.

GRUB produced by this workflow is not Secure Boot signed. A production Secure
Boot chain requires a trusted shim and a GRUB binary signed by an accepted key.
