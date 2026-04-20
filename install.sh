#!/bin/bash

INSTALL_DIR="/root/alphasys"
BIN_LINK="/usr/local/bin/alphasys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must be run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: install.sh must be run as root." >&2
    exit 1
fi

echo "Copying project to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
cp -r "${SCRIPT_DIR}/application" "${INSTALL_DIR}/"
cp -r "${SCRIPT_DIR}/resources"   "${INSTALL_DIR}/"

echo "Setting permissions ..."
chmod +x "${INSTALL_DIR}/application/alphasys"

echo "Creating symlink: ${BIN_LINK} -> ${INSTALL_DIR}/application/alphasys"
ln -sf "${INSTALL_DIR}/application/alphasys" "${BIN_LINK}"

echo "Done. Run: alphasys --help"
