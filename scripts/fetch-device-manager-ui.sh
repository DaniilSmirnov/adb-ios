#!/usr/bin/env bash
set -euo pipefail

: "${DEVICE_MANAGER_UI_URL:?Set DEVICE_MANAGER_UI_URL to a versioned DeviceManagerUI archive}"
: "${DEVICE_MANAGER_UI_SHA256:?Set DEVICE_MANAGER_UI_SHA256 to the archive SHA-256}"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${DEVICE_MANAGER_UI_DESTINATION:-${repository_root}/Resources/DeviceManagerUI}"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT

archive="${temporary_root}/DeviceManagerUI.tar.gz"
extracted="${temporary_root}/extracted"

curl --fail --location --retry 3 --silent --show-error "${DEVICE_MANAGER_UI_URL}" --output "${archive}"
printf '%s  %s\n' "${DEVICE_MANAGER_UI_SHA256}" "${archive}" | shasum --algorithm 256 --check --status

mkdir -p "${extracted}"
tar --extract --gzip --file "${archive}" --directory "${extracted}"

source_directory="${extracted}"
if [[ -d "${extracted}/DeviceManagerUI" ]]; then
  source_directory="${extracted}/DeviceManagerUI"
fi

test -s "${source_directory}/index.html"
test -s "${source_directory}/device-manager.js"

mkdir -p "$(dirname "${destination}")"
rm -rf "${destination}"
mv "${source_directory}" "${destination}"
echo "Installed DeviceManagerUI into ${destination}"
