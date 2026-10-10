#!/usr/bin/env bash
# run.sh: build (if needed) and run the server locally with env passthrough.
# Examples:
#   scripts/run.sh
#   PORT=9090 LAB_ADMIN_TOKEN=secret scripts/run.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -x bin/v-http-lab ]]; then
	scripts/build.sh
fi

exec ./bin/v-http-lab
