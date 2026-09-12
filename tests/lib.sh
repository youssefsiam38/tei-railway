#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for tei-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:3000}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

# KEY_FILE holds the API key and is never printed.
api_key() { cat "${KEY_FILE:?KEY_FILE not set}"; }

http_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$@"; }
auth_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "Authorization: Bearer $(api_key)" "$@"; }
auth_body()  { curl -s --max-time 120 -H "Authorization: Bearer $(api_key)" "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

wait_for_log() {
  local pattern=$1 service=${2:-tei} timeout=${3:-180} start
  start=$(date +%s)
  while :; do
    compose logs --no-color "$service" 2>/dev/null | grep -q -- "$pattern" && return 0
    [ $(( $(date +%s) - start )) -ge "$timeout" ] && return 1
    sleep 2
  done
}

# embed TEXT... -> the raw response body
embed() {
  local payload; payload=$(jq -nc --args '{inputs: $ARGS.positional}' "$@")
  auth_body -X POST -H 'Content-Type: application/json' --data "$payload" "$BASE_URL/embed"
}
# openai_embed TEXT -> the raw response body from the OpenAI-compatible route
openai_embed() {
  auth_body -X POST -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg i "$1" '{input: $i, model: "tei"}')" "$BASE_URL/v1/embeddings"
}
info() { auth_body "$BASE_URL/info"; }

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
