#!/bin/bash
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="${SCRIPT_DIR}"

git -C "${ROOT_DIR}" submodule update --init --recursive

cd "${ROOT_DIR}"
source setup ast2700-a1

LAYER_DIR="${ROOT_DIR}/meta-snow"

if [ ! -d "${LAYER_DIR}" ]; then
    echo "[ERROR] Layer directory not found: ${LAYER_DIR}"
    exit 1
fi

if grep -q "${LAYER_DIR}" conf/bblayers.conf; then
    echo "[OK] meta-snow already in bblayers.conf"
else
    echo "[ADD] meta-snow -> ${LAYER_DIR}"
    bitbake-layers add-layer "${LAYER_DIR}"
fi
