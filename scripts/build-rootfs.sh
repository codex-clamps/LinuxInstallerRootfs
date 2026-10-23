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
container_id="$(docker run --platform linux/amd64 --detach --entrypoint /bin/sh "${source_image}" -c 'while :; do sleep 3600; done')"
docker cp scripts/provision-rootfs.sh "${container_id}:/tmp/provision-rootfs.sh"
if [[ -d scripts/provision ]]; then
  docker cp scripts/provision "${container_id}:/tmp/provision"
fi
docker exec "${container_id}" /bin/sh /tmp/provision-rootfs.sh "${distro_id}"
docker export "${container_id}" | zstd --threads=0 -19 -o "${output_directory}/${archive_name}"
sha256sum "${output_directory}/${archive_name}" | awk '{print $1}' > "${output_directory}/${archive_name}.sha256"
