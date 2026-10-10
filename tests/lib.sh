#!/usr/bin/env bash
# lib.sh: shared helpers for the v-http-lab curl test suites.
#
# Usage:
#   ./tests/<group>.sh              # runs all cases of one group
#   LAB_TEST_MODE=smoke  ...        # run only cases tagged [smoke]
#   LAB_TEST_MODE=errors ...        # run only cases tagged [errors]
#   LAB_TEST_MODE=limits ...        # run only cases tagged [limits]
#
# When BASE_URL is set the suite runs against that server as-is.
# Otherwise a fresh server is started from $VHTTP_BIN on TEST_PORT with a
# deterministic seed (restart = clean state) and stopped on exit.

BASE_URL="${BASE_URL:-}"
TEST_PORT="${TEST_PORT:-18080}"
LAB_ADMIN_TOKEN="${LAB_ADMIN_TOKEN:-test-admin-token}"
MODE="${LAB_TEST_MODE:-all}"
VHTTP_BIN="${VHTTP_BIN:-bin/v-http-lab}"

PASS=0
FAIL=0
SKIP=0

SERVER_PID=""
SERVER_LOG=""

should_run() {
	case "$MODE" in
	all) return 0 ;;
	smoke) [[ "$1" == "smoke" ]] ;;
	errors) [[ "$1" == "errors" ]] ;;
	limits) [[ "$1" == "limits" ]] ;;
	*) return 0 ;;
	esac
}

start_server() {
	if [[ -n "$BASE_URL" ]]; then
		echo "using external server: $BASE_URL"
		return 0
	fi
	if [[ ! -x "$VHTTP_BIN" ]]; then
		echo "FATAL: $VHTTP_BIN not found; run scripts/build.sh first" >&2
		exit 1
	fi
	SERVER_LOG="$(mktemp /tmp/v-http-lab-test.XXXXXX.log)"
	PORT="$TEST_PORT" LAB_ADMIN_TOKEN="$LAB_ADMIN_TOKEN" \
		setsid "$VHTTP_BIN" >"$SERVER_LOG" 2>&1 </dev/null &
	SERVER_PID=$!
	for _ in $(seq 1 50); do
		if curl -sf -m 1 "http://127.0.0.1:${TEST_PORT}/health" >/dev/null 2>&1; then
			BASE_URL="http://127.0.0.1:${TEST_PORT}"
			echo "server started (pid $SERVER_PID, port $TEST_PORT, log $SERVER_LOG)"
			return 0
		fi
		sleep 0.1
	done
	echo "FATAL: test server did not become healthy; log follows" >&2
	cat "$SERVER_LOG" >&2
	stop_server
	exit 1
}

stop_server() {
	if [[ -n "$SERVER_PID" ]]; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
		SERVER_PID=""
	fi
	if [[ -n "$SERVER_LOG" ]]; then
		rm -f "$SERVER_LOG"
		SERVER_LOG=""
	fi
}

trap stop_server EXIT

# http METHOD PATH [curl args...] -> sets STATUS, HEADERS, BODY
http() {
	local method="$1" path="$2"
	shift 2
	local tmp
	tmp="$(mktemp)"
	HEADERS="$(curl -sS -m 20 -o "$tmp" -D - -X "$method" "$BASE_URL$path" "$@" 2>&1)" || true
	BODY="$(cat "$tmp")"
	rm -f "$tmp"
	STATUS="$(head -n 1 <<<"$HEADERS" | tr -d '\r' | awk '{print $2}')"
}

# timed METHOD PATH [curl args...] -> sets STATUS, TOTAL_TIME
timed() {
	local method="$1" path="$2"
	shift 2
	local out
	out="$(curl -sS -m 20 -o /dev/null -w '%{http_code} %{time_total}' -X "$method" "$BASE_URL$path" "$@" 2>&1)" || true
	STATUS="${out%% *}"
	TOTAL_TIME="${out##* }"
}

expect_status() {
	local tag="$1" expected="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if [[ "$STATUS" == "$expected" ]]; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (status $STATUS)"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (expected status $expected, got ${STATUS:-none}; body: $(head -c 200 <<<"$BODY"))"
	fi
}

expect_body_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qF -- "$needle" <<<"$BODY"; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (body contains '${needle}')"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (body does not contain '${needle}'; body: $(head -c 200 <<<"$BODY"))"
	fi
}

expect_body_not_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qF -- "$needle" <<<"$BODY"; then
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (body unexpectedly contains '${needle}')"
	else
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (body does not contain '${needle}')"
	fi
}

expect_header_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qi -- "$needle" <<<"$HEADERS"; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (header contains '${needle}')"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (header does not contain '${needle}'; headers: $(head -c 300 <<<"$HEADERS"))"
	fi
}

expect_header_not_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qi -- "$needle" <<<"$HEADERS"; then
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (header unexpectedly contains '${needle}')"
	else
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (header does not contain '${needle}')"
	fi
}

expect_body_size() {
	local tag="$1" expected="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	local size
	size="$(wc -c <<<"$BODY")"
	# wc -c via herestring counts the trailing newline added by <<<.
	size=$((size - 1))
	if [[ "$size" == "$expected" ]]; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (body size $size)"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (expected body size $expected, got $size)"
	fi
}

expect_min_time() {
	local tag="$1" seconds="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if awk -v t="$TOTAL_TIME" -v s="$seconds" 'BEGIN { exit !(t >= s) }'; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (took ${TOTAL_TIME}s, >= ${seconds}s)"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (took ${TOTAL_TIME}s, expected >= ${seconds}s)"
	fi
}

# Log checks only work against the lib-managed server.
expect_log_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if [[ -z "$SERVER_LOG" ]]; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qF -- "$needle" "$SERVER_LOG"; then
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (log contains '${needle}')"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (log does not contain '${needle}')"
	fi
}

expect_log_not_contains() {
	local tag="$1" needle="$2" desc="$3"
	if ! should_run "$tag"; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if [[ -z "$SERVER_LOG" ]]; then
		SKIP=$((SKIP + 1))
		return 0
	fi
	if grep -qF -- "$needle" "$SERVER_LOG"; then
		FAIL=$((FAIL + 1))
		echo "FAIL [$tag] $desc (log unexpectedly contains '${needle}')"
	else
		PASS=$((PASS + 1))
		echo "PASS [$tag] $desc (log does not contain '${needle}')"
	fi
}

summary() {
	echo "----"
	echo "group:   ${0##*/}"
	echo "mode:    $MODE"
	echo "passed:  $PASS"
	echo "failed:  $FAIL"
	echo "skipped: $SKIP"
	if [[ "$FAIL" -gt 0 ]]; then
		exit 1
	fi
	exit 0
}
