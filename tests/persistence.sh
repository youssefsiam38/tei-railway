#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the downloaded model survives recreating the container, so a redeploy does not fetch
# it again. The model cache is the only durable state this service has.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
KEY_FILE="$TEST_TMP/key"; export KEY_FILE
printf '%s' 'local-test-only-tei-api-key' > "$KEY_FILE"

section "fresh stack (empty model cache)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/health" 200 600 || die "not ready"
cold=$(( $(date +%s) - t0 )); pass "first start took ${cold}s including the model download"

section "the model landed in the volume"
cached=$(compose exec -T tei sh -c 'ls -1 /data 2>/dev/null' | tr -d '\r')
assert_contains "the hub cache is populated" "models--BAAI--bge-small-en-v1.5" "$cached"
e=$(embed "a sentence about railways")
assert_eq "embeddings work before the recreate" "384" "$(jq -r '.[0] | length' <<<"$e")"

section "recreate the container on the same volume"
compose down >/dev/null
t1=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/health" 200 600 || die "not ready after recreate"
warm=$(( $(date +%s) - t1 )); pass "second start took ${warm}s"

section "verify"
cached=$(compose exec -T tei sh -c 'ls -1 /data 2>/dev/null' | tr -d '\r')
assert_contains "the model is still cached" "models--BAAI--bge-small-en-v1.5" "$cached"
e=$(embed "a sentence about railways")
assert_eq "embeddings still work" "384" "$(jq -r '.[0] | length' <<<"$e")"
assert_eq "the key is unchanged" "200" "$(auth_code "$BASE_URL/info")"
assert_eq "anonymous is still refused" "401" "$(http_code "$BASE_URL/info")"
[ "$warm" -le "$cold" ] && pass "the warm start was no slower than the cold one (${warm}s vs ${cold}s)" \
  || fail "the warm start was slower (${warm}s vs ${cold}s); the cache may not be persisting"
summary
