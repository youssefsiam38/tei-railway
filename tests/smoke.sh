#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set TEI_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_KEY='local-test-only-tei-api-key'
umask 077
KEY_FILE="$TEST_TMP/key"; export KEY_FILE
printf '%s' "$LOCAL_KEY" > "$KEY_FILE"

section "fresh stack (empty model cache)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/health" 200 600 && pass "health route answers" || { compose logs --no-color tei | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "start-up"
logs=$(compose logs --no-color tei)
assert_contains "the model and cache were reported" "model BAAI/bge-small-en-v1.5" "$logs"
assert_contains "the key requirement was reported" "API key required for every route except" "$logs"
# The router prints `api_key: Some("...")` among its parsed arguments on every start. The wrapper
# filters its output so that never reaches the platform's log collector.
assert_not_contains "the key is not in the logs" "$LOCAL_KEY" "$logs"
assert_contains "and the line it came from is still there, redacted" "REDACTED" "$logs"

section "the work routes need the key"
# Upstream answers every request when no key is set. This is the whole reason the wrapper insists
# on one, so each route that costs CPU is checked rather than a representative sample.
body='{"inputs":["hello"]}'
for route in /embed /embed_all /embed_sparse /predict /similarity /tokenize; do
  assert_eq "anonymous $route refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data "$body" "$BASE_URL$route")"
done
assert_eq "anonymous /v1/embeddings refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{"input":"hello","model":"tei"}' "$BASE_URL/v1/embeddings")"
assert_eq "anonymous /embeddings refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{"input":"hello","model":"tei"}' "$BASE_URL/embeddings")"
assert_eq "anonymous /info refused" "401" "$(http_code "$BASE_URL/info")"
assert_eq "a wrong key is refused" "401" "$(http_code -H 'Authorization: Bearer not-the-key-at-all' -X POST -H 'Content-Type: application/json' --data "$body" "$BASE_URL/embed")"
assert_eq "a key without the Bearer prefix is refused" "401" "$(http_code -H "Authorization: $LOCAL_KEY" -X POST -H 'Content-Type: application/json' --data "$body" "$BASE_URL/embed")"

section "the probe routes stay open, and publish nothing"
# Upstream exempts these deliberately so an orchestrator can reach them; the template's healthcheck
# depends on it. They are checked here so a future upstream change does not go unnoticed.
assert_eq "health is open" "200" "$(http_code "$BASE_URL/health")"
assert_eq "root is open and is the same health route" "200" "$(http_code "$BASE_URL/")"
assert_eq "ping is open" "200" "$(http_code "$BASE_URL/ping")"
assert_eq "metrics is open" "200" "$(http_code "$BASE_URL/metrics")"
assert_not_contains "metrics do not leak the key" "$LOCAL_KEY" "$(curl -s --max-time 30 "$BASE_URL/metrics")"

section "embeddings with the key"
i=$(info)
assert_eq "the served model is the one configured" "BAAI/bge-small-en-v1.5" "$(jq -r '.model_id' <<<"$i")"
assert_eq "it is an embedding model" "embedding" "$(jq -r '.model_type | keys[0]' <<<"$i")"

e=$(embed "a sentence about railways" "a sentence about databases")
assert_eq "two inputs give two vectors" "2" "$(jq -r 'length' <<<"$e")"
dim=$(jq -r '.[0] | length' <<<"$e")
assert_eq "bge-small returns 384 dimensions" "384" "$dim"
assert_eq "the values are numbers" "number" "$(jq -r '.[0][0] | type' <<<"$e")"
# A normalised embedding has unit length; this is the cheapest check that the model really ran.
norm=$(jq -r '.[0] | map(. * .) | add | sqrt | . * 1000 | round' <<<"$e")
[ "$norm" -ge 995 ] && [ "$norm" -le 1005 ] && pass "the vector is normalised (|v| = ${norm}/1000)" || fail "the vector is not normalised (|v| = ${norm}/1000)"

o=$(openai_embed "a sentence about railways")
assert_eq "the OpenAI-compatible route answers" "list" "$(jq -r '.object' <<<"$o")"
assert_eq "and returns one embedding" "1" "$(jq -r '.data | length' <<<"$o")"
assert_eq "of the same width" "384" "$(jq -r '.data[0].embedding | length' <<<"$o")"

section "oversized payloads are refused"
# Upstream caps the body at PAYLOAD_LIMIT (2 MB by default) and answers 400, not 413; the assertion
# is on the refusal rather than the exact code, but a 200 here would mean the cap is not applied.
big=$(python3 -c "print('x' * 3000000)")
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "Authorization: Bearer $(api_key)" \
  -X POST -H 'Content-Type: application/json' --data "$(jq -nc --arg t "$big" '{inputs: [$t]}')" "$BASE_URL/embed" || true)
case "$code" in 400|413) pass "a payload over the limit is rejected ($code)" ;; *) fail "a payload over the limit answered $code" ;; esac

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 tei; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q tei)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start tei; wait_for_code "$BASE_URL/health" 200 300 && pass "restarted" || die "did not restart"

section "fail-fast validation"
img=$(compose config --images | head -1)
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img; then fail "should fail without a key"; else pass "exits without API_KEY"; fi
assert_contains "explains why a key is required" "anyone who finds the URL can run embeddings" "$(cat "$TEST_TMP/ff.log")"
if run_img -e API_KEY=short; then fail "should reject a short key"; else pass "rejects a short key"; fi
assert_contains "states the length rule" "at least 16 characters" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "API_KEY=a key with spaces in it"; then fail "should reject a key with spaces"; else pass "rejects a key with spaces"; fi
if run_img -e "API_KEY=$LOCAL_KEY" -e PORT=9000; then fail "should refuse a metrics port collision"; else pass "refuses a collision with the metrics port"; fi
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
# An explicitly empty value must not fall through to the image default, or a typo would quietly
# serve a different model than the one the deployer thinks they set.
if run_img -e "API_KEY=$LOCAL_KEY" -e MODEL_ID=; then fail "should reject an empty model"; else pass "rejects an empty MODEL_ID"; fi
assert_contains "explains the empty model" "MODEL_ID is set but empty" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed" "$LOCAL_KEY" "$(cat "$TEST_TMP/ff.log")"

section "the opt-out is deliberate and loud"
docker rm -f tei-open >/dev/null 2>&1 || true
vol=$(docker inspect "$(compose ps -q tei)" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}')
docker run -d --name tei-open -e TEI_ALLOW_PUBLIC=true -e PORT=3010 -p 127.0.0.1:3010:3010 -v "${vol}:/data" "$img" >/dev/null
for _ in $(seq 1 100); do [ "$(http_code --max-time 5 "http://127.0.0.1:3010/health" || true)" = "200" ] && break; sleep 3; done
assert_eq "an open instance embeds anonymously" "200" "$(http_code -X POST -H 'Content-Type: application/json' --data '{"inputs":["hello"]}' "http://127.0.0.1:3010/embed")"
assert_contains "and says so in the log" "No API key is set" "$(docker logs tei-open 2>&1)"
docker rm -f tei-open >/dev/null

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.tei-railway.upstream.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "upstream licence shipped" "Apache License" "$(compose exec -T tei head -1 /usr/share/licenses/tei-railway/TEI-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep tei-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
