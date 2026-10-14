#!/usr/bin/env bash
set -euo pipefail

output_directory="dist"
work_directory="work/installer-runtime"
root_directory="${work_directory}/root"
image_name="linux-installer-runtime:local"
container_id=""

cleanup() {
  if [[ -n "${container_id}" ]]; then
    docker rm -f "${container_id}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install --yes cpio gzip
fi

rm -rf "${work_directory}"
mkdir -p "${output_directory}" "${root_directory}"

docker build --platform linux/amd64 --file docker/installer-runtime.Dockerfile --tag "${image_name}" .
container_id="$(docker create --platform linux/amd64 "${image_name}")"

docker cp "${container_id}:/boot/vmlinuz-lts" "${output_directory}/installer.vmlinuz"
docker export "${container_id}" | tar -C "${root_directory}" -xf -
rm -f "${root_directory}/boot/vmlinuz-lts"

(
  cd "${root_directory}"
  find . -print0 | cpio --null --create --format=newc --quiet | gzip -9
) > "${output_directory}/installer.initrd"

sha256sum "${output_directory}/installer.vmlinuz" | awk '{print $1}' > "${output_directory}/installer.vmlinuz.sha256"
sha256sum "${output_directory}/installer.initrd" | awk '{print $1}' > "${output_directory}/installer.initrd.sha256"
