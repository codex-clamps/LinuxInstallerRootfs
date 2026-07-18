#!/usr/bin/env bash
set -euo pipefail

dist_directory="${1:?artifact directory is required}"
manifest_path="${2:?manifest path is required}"
repository="${3:?GitHub repository is required}"
release_tag="${4:?release tag is required}"
entries_file="$(mktemp)"

cleanup() {
  rm -f "${entries_file}"
}
trap cleanup EXIT

architecture="$(jq -r '.architecture' distros.json)"

while IFS= read -r distro; do
  id="$(jq -r '.id' <<<"${distro}")"
  archive_name="${id}-${architecture}.rootfs.tar.zst"
  archive_path="${dist_directory}/${archive_name}"
  checksum_path="${archive_path}.sha256"

  if [[ ! -f "${archive_path}" || ! -f "${checksum_path}" ]]; then
    echo "Missing artifact for ${id}" >&2
    exit 1
  fi

  jq -n \
    --arg id "${id}" \
    --arg distroName "$(jq -r '.distroName' <<<"${distro}")" \
    --arg version "$(jq -r '.version' <<<"${distro}")" \
    --arg description "$(jq -r '.description' <<<"${distro}")" \
    --arg iconUrl "$(jq -r '.iconUrl' <<<"${distro}")" \
    --arg fileName "${archive_name}" \
    --arg sha256 "$(tr -d '[:space:]' < "${checksum_path}")" \
    --arg downloadUrl "https://github.com/${repository}/releases/download/${release_tag}/${archive_name}" \
    --argjson size "$(stat -c '%s' "${archive_path}")" \
    '{id: $id, distroName: $distroName, version: $version, description: $description, iconUrl: $iconUrl, fileName: $fileName, sha256: $sha256, downloadUrl: $downloadUrl, size: $size}' \
    >> "${entries_file}"
done < <(jq -c '.distros[]' distros.json)

jq -s \
  --arg generatedAt "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg architecture "${architecture}" \
  '{schemaVersion: 1, generatedAt: $generatedAt, architecture: $architecture, distros: .}' \
  "${entries_file}" > "${manifest_path}"
