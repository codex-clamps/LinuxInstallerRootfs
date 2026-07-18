#!/usr/bin/env bash
set -euo pipefail

version="1.9"
expected_commit="0d913acaa54134e7dcdfc1f19a057f2752d67c75"
source_directory="work/winbtrfs"
build_directory="work/winbtrfs-build"
package_directory="work/winbtrfs-package"
output_directory="dist"
archive_name="winbtrfs-${version}-x64-unsigned.zip"

sudo apt-get update
sudo apt-get install --yes cmake mingw-w64 ninja-build zip

rm -rf work
mkdir -p "${output_directory}"
git clone --branch "v${version}" --depth 1 --recurse-submodules   https://github.com/maharmstone/btrfs.git "${source_directory}"

actual_commit="$(git -C "${source_directory}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${expected_commit}" ]]; then
  echo "Unexpected WinBtrfs commit: ${actual_commit}" >&2
  exit 1
fi

sudo mkdir -p /usr/x86_64-w64-mingw32/usr/include
sudo ln -sfn /usr/x86_64-w64-mingw32/include/ddk   /usr/x86_64-w64-mingw32/usr/include/ddk

cmake   -S "${source_directory}"   -B "${build_directory}"   -G Ninja   -DCMAKE_TOOLCHAIN_FILE="${source_directory}/mingw-amd64.cmake"   -DCMAKE_BUILD_TYPE=Release   -DWITH_TEST=OFF
cmake --build "${build_directory}" --parallel

mkdir -p "${package_directory}"
cp "${build_directory}/btrfs.sys" "${package_directory}/"
cp "${build_directory}/mkbtrfs.exe" "${package_directory}/"
cp "${build_directory}/shellbtrfs.dll" "${package_directory}/"
cp "${build_directory}/ubtrfs.dll" "${package_directory}/"
cp "${source_directory}/src/btrfs.inf" "${package_directory}/"
cp "${source_directory}/src/btrfs-vol.inf" "${package_directory}/"
cp "${source_directory}/LICENCE" "${package_directory}/"
cat > "${package_directory}/UNSIGNED.txt" <<'NOTICE'
This package was built from WinBtrfs v1.9 source by GitHub Actions.
The driver and catalog are not code-signed. Do not install this package on a
normal Windows system. Use the separately published upstream-signed package.
NOTICE

(
  cd "${package_directory}"
  zip -9 -r "../../${output_directory}/${archive_name}" .
)
sha256sum "${output_directory}/${archive_name}" | awk '{print $1}' > "${output_directory}/${archive_name}.sha256"
