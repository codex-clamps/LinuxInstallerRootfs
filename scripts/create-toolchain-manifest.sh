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

while IFS= read -r artifact; do
  file_name="$(jq -r '.fileName' <<<"${artifact}")"
  file_path="${dist_directory}/${file_name}"
  checksum_path="${file_path}.sha256"

  if [[ ! -f "${file_path}" || ! -f "${checksum_path}" ]]; then
    echo "Missing toolchain artifact: ${file_name}" >&2
    exit 1
  fi

  jq -n     --arg id "$(jq -r '.id' <<<"${artifact}")"     --arg displayName "$(jq -r '.displayName' <<<"${artifact}")"     --arg version "$(jq -r '.version' <<<"${artifact}")"     --arg kind "$(jq -r '.kind' <<<"${artifact}")"     --arg platform "$(jq -r '.platform' <<<"${artifact}")"     --arg fileName "${file_name}"     --arg sha256 "$(tr -d '[:space:]' < "${checksum_path}")"     --arg sourceUrl "$(jq -r '.sourceUrl' <<<"${artifact}")"     --arg license "$(jq -r '.license' <<<"${artifact}")"     --arg notes "$(jq -r '.notes' <<<"${artifact}")"     --arg downloadUrl "https://github.com/${repository}/releases/download/${release_tag}/${file_name}"     --argjson size "$(stat -c '%s' "${file_path}")"     --argjson requiredForInstall "$(jq '.requiredForInstall' <<<"${artifact}")"     --argjson signed "$(jq '.signed' <<<"${artifact}")"     '{id: $id, displayName: $displayName, version: $version, kind: $kind, platform: $platform, fileName: $fileName, size: $size, sha256: $sha256, downloadUrl: $downloadUrl, sourceUrl: $sourceUrl, license: $license, notes: $notes, requiredForInstall: $requiredForInstall, signed: $signed}'     >> "${entries_file}"
done < <(jq -c '.artifacts[]' toolchains.json)

jq -s   --arg generatedAt "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"   '{schemaVersion: 1, generatedAt: $generatedAt, artifacts: .}'   "${entries_file}" > "${manifest_path}"
