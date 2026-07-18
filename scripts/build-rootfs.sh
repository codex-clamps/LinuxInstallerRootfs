#!/usr/bin/env bash
set -euo pipefail

distro_id="${1:?distro id is required}"
source_image="${2:?source image is required}"
architecture="x86_64"
output_directory="dist"
archive_name="${distro_id}-${architecture}.rootfs.tar.zst"
container_id=""

cleanup() {
  if [[ -n "${container_id}" ]]; then
    docker rm -f "${container_id}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "${output_directory}"
docker pull --platform linux/amd64 "${source_image}"
container_id="$(docker create --platform linux/amd64 "${source_image}")"
docker export "${container_id}" | zstd --threads=0 -19 -o "${output_directory}/${archive_name}"
sha256sum "${output_directory}/${archive_name}" | awk '{print $1}' > "${output_directory}/${archive_name}.sha256"
