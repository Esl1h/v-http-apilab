#!/usr/bin/env bash
# test-smoke.sh: run the smoke (happy path) cases of every test group.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -x bin/v-http-lab ]]; then
	echo "FATAL: bin/v-http-lab not found; run scripts/build.sh first" >&2
	exit 1
fi

rc=0
for group in tests/*.sh; do
	[[ "$group" == "tests/lib.sh" ]] && continue
	LAB_TEST_MODE=smoke "$group" || rc=1
done
exit "$rc"
