#!/usr/bin/env bash
# build.sh: compile the release binary into bin/v-http-apilab.
# The V toolchain version is baked into /version at build time.
set -euo pipefail

cd "$(dirname "$0")/.."

V_BIN="${V:-v}"

if ! command -v "$V_BIN" >/dev/null 2>&1; then
	echo "FATAL: V compiler not found (${V_BIN}); see README.md for the pinned version" >&2
	exit 1
fi

V_VERSION="$($V_BIN version 2>/dev/null || echo unknown)"

echo "building with: ${V_VERSION}"
mkdir -p bin
V_VERSION="$V_VERSION" "$V_BIN" -prod . -o bin/v-http-apilab
echo "built: bin/v-http-apilab"
