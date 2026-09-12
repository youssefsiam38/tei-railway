#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: KEY_FILE=/path/to/file holding the API key
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over, so wait rather than
# racing the cutover when this runs straight after a deploy.
wait_for_code "$BASE_URL/health" 200 600 || true
assert_eq "health route answers over https" "200" "$(http_code "$BASE_URL/health")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/health" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/health")"

section "the instance is not open to the internet"
body='{"inputs":["hello"]}'
for route in /embed /embed_all /predict /similarity /tokenize; do
  assert_eq "anonymous $route refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data "$body" "$BASE_URL$route")"
done
assert_eq "anonymous /v1/embeddings refused" "401" "$(http_code -X POST -H 'Content-Type: application/json' --data '{"input":"hello","model":"tei"}' "$BASE_URL/v1/embeddings")"
assert_eq "anonymous /info refused" "401" "$(http_code "$BASE_URL/info")"
assert_eq "a wrong key is refused" "401" "$(http_code -H 'Authorization: Bearer not-the-key-at-all' "$BASE_URL/info")"
assert_eq "the probe route stays open" "200" "$(http_code "$BASE_URL/health")"

if [ -n "${KEY_FILE:-}" ]; then
  section "embeddings through the public domain"
  i=$(info)
  assert_eq "the served model is reported" "BAAI/bge-small-en-v1.5" "$(jq -r '.model_id' <<<"$i")"
  e=$(embed "a sentence about railways" "a sentence about databases")
  assert_eq "two inputs give two vectors" "2" "$(jq -r 'length' <<<"$e")"
  assert_eq "of 384 dimensions" "384" "$(jq -r '.[0] | length' <<<"$e")"
  o=$(openai_embed "a sentence about railways")
  assert_eq "the OpenAI-compatible route answers" "list" "$(jq -r '.object' <<<"$o")"
fi
summary
