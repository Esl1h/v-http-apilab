#!/usr/bin/env bash
# test-limits.sh: run the boundary/limit cases of every test group
# (body size caps, pagination bounds, query limits, slow/large ceilings).
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -x bin/v-http-apilab ]]; then
	echo "FATAL: bin/v-http-apilab not found; run scripts/build.sh first" >&2
	exit 1
fi

rc=0
for group in tests/*.sh; do
	[[ "$group" == "tests/lib.sh" ]] && continue
	LAB_TEST_MODE=limits "$group" || rc=1
done
exit "$rc"
