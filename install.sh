#!/bin/bash

INSTALL_DIR="/root/alphasys"
BIN_LINK="/usr/local/bin/alphasys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must be run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: install.sh must be run as root." >&2
    exit 1
fi

echo "[install] Copying project to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
cp -r "${SCRIPT_DIR}/bin"       "${INSTALL_DIR}/"
cp -r "${SCRIPT_DIR}/resources" "${INSTALL_DIR}/"

echo "[install] Setting permissions ..."
chmod +x "${INSTALL_DIR}/bin/alphasys"

echo "[install] Creating symlink: ${BIN_LINK} -> ${INSTALL_DIR}/bin/alphasys"
ln -sf "${INSTALL_DIR}/bin/alphasys" "${BIN_LINK}"

echo "[install] Done. Run: alphasys --help"
