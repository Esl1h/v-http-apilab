#!/usr/bin/env bash
# test-errors.sh: run the error-path (400/401/403/404/405/413/415/422/431)
# cases of every test group.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -x bin/v-http-lab ]]; then
	echo "FATAL: bin/v-http-lab not found; run scripts/build.sh first" >&2
	exit 1
fi

rc=0
for group in tests/*.sh; do
	[[ "$group" == "tests/lib.sh" ]] && continue
	LAB_TEST_MODE=errors "$group" || rc=1
done
exit "$rc"
