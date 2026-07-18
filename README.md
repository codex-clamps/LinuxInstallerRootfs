# LinuxInstallerRootfs

Prebuilt root filesystem archives consumed by
[LinuxInstallerForWindows](https://github.com/codex-clamps/LinuxInstallerForWindows).

GitHub Actions builds the app's supported distributions for linux/amd64, compresses
each exported filesystem as rootfs.tar.zst, calculates a SHA-256 checksum, and
publishes the files to the stable rootfs-latest release. The generated manifest.json
is the API used by the desktop app.

These files are minimal container-derived root filesystems, not bootable disk images.
The installer is responsible for extracting an archive into the target Linux
filesystem and configuring the kernel, initramfs, users, networking, and bootloader.

## Supported distributions

- Ubuntu 24.04 LTS
- Fedora 40
- Debian 12
- Manjaro Rolling
- Arch Linux Rolling

## Rebuild

The workflow runs when its inputs change, on the first day of each month, or through
the GitHub Actions workflow_dispatch button. Edit distros.json to change the build
matrix or user-facing metadata.

## Release contract

The rootfs-latest release contains one archive and checksum per distribution plus
manifest.json. Consumers must verify the manifest-provided SHA-256 value before
using a downloaded archive.
