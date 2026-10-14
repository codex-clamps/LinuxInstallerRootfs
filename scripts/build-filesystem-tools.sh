#!/usr/bin/env bash
set -euo pipefail

output_directory="dist"
archive_name="filesystem-tools-x86_64.tar.zst"
image_name="linux-installer-filesystem-tools:local"
container_id=""

cleanup() {
  if [[ -n "${container_id}" ]]; then
    docker rm -f "${container_id}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install --yes zstd
fi

mkdir -p "${output_directory}"
docker build --no-cache --platform linux/amd64 --file docker/filesystem-tools.Dockerfile --tag "${image_name}" .
container_id="$(docker create --platform linux/amd64 "${image_name}")"
docker export "${container_id}" | zstd -f --threads=0 -19 -o "${output_directory}/${archive_name}"
sha256sum "${output_directory}/${archive_name}" | awk '{print $1}' > "${output_directory}/${archive_name}.sha256"
