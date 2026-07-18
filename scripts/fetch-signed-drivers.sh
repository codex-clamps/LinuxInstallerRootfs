#!/usr/bin/env bash
set -euo pipefail

output_directory="dist"
winbtrfs_name="winbtrfs-1.9-x64-signed.zip"
ext4fsd_name="ext4fsd-0.71-signed-setup.exe"
winbtrfs_sha256="673b0ecc23634d85213ba46e309bfb788ac83fcc14e4976773b324592401303a"
ext4fsd_sha256="3c127f8e70c6b056a0185850efb71b9c45d2ff493b7df6b7b648eb89ec84214d"

mkdir -p "${output_directory}"
curl --fail --location   https://github.com/maharmstone/btrfs/releases/download/v1.9/btrfs-1.9.zip   --output "${output_directory}/${winbtrfs_name}"
curl --fail --location   https://github.com/bobranten/Ext4Fsd/releases/download/v0.71/Ext2Fsd-0.71-setup.exe   --output "${output_directory}/${ext4fsd_name}"

echo "${winbtrfs_sha256}  ${output_directory}/${winbtrfs_name}" | sha256sum --check
echo "${ext4fsd_sha256}  ${output_directory}/${ext4fsd_name}" | sha256sum --check
printf '%s\n' "${winbtrfs_sha256}" > "${output_directory}/${winbtrfs_name}.sha256"
printf '%s\n' "${ext4fsd_sha256}" > "${output_directory}/${ext4fsd_name}.sha256"
