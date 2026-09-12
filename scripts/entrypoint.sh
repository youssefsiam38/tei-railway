#!/bin/bash
# tei-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. make the model cache directory the volume will hold
#   3. exec the upstream router
#
# Text Embeddings Inference answers every request unless `--api-key` is set, and it is not set
# unless you set it. On a public hostname that is an open embeddings endpoint running on the
# deployer's CPU. Upstream already exempts the right routes from the key -- `/health`, `/`, `/ping`
# and `/metrics` are public and everything that does work is not -- so the wrapper only has to make
# sure the key exists.
set -uo pipefail

# Informational lines go to stdout and only failures to stderr. Railway derives a log's severity
# from the stream it arrived on, so a start-up message written to stderr is shown to the deployer
# in red as though something had gone wrong.
log()  { printf '[tei-railway] %s\n' "$*"; }
fail() { printf '[tei-railway] FATAL: %s\n' "$*" >&2; exit 1; }

# An explicitly empty MODEL_ID is a mistake worth catching, and `${VAR:=default}` would silently
# replace it, so the emptiness check has to come before the default.
if [ -n "${MODEL_ID+set}" ] && [ -z "$MODEL_ID" ]; then
  printf '[tei-railway] FATAL: %s\n' "MODEL_ID is set but empty. The router will not start without a model; remove the variable to use this image's default." >&2
  exit 1
fi
: "${MODEL_ID:=BAAI/bge-small-en-v1.5}"
: "${HUGGINGFACE_HUB_CACHE:=/data}"
: "${HOSTNAME:=0.0.0.0}"

# Railway probes its healthcheck against PORT (8080 when unset), and the router reads PORT itself,
# so there is nothing to translate -- only something to check.
PUBLIC_PORT="${PORT:-3000}"
case "$PUBLIC_PORT" in
  ''|*[!0-9]*) fail "PORT must be a number, got \"$PUBLIC_PORT\"" ;;
esac
: "${PROMETHEUS_PORT:=9000}"
if [ "$PUBLIC_PORT" = "$PROMETHEUS_PORT" ]; then
  fail "PORT and PROMETHEUS_PORT are both $PUBLIC_PORT. The API and the metrics listener cannot share a port; change PROMETHEUS_PORT."
fi

ALLOW_PUBLIC="${TEI_ALLOW_PUBLIC:-false}"
if [ "$ALLOW_PUBLIC" != "true" ]; then
  [ -n "${API_KEY:-}" ] || fail "missing required variable: API_KEY. Text Embeddings Inference answers every request unless an API key is set, so without this anyone who finds the URL can run embeddings on your instance. Set a key, or set TEI_ALLOW_PUBLIC=true if you really want an open endpoint."
  [ "${#API_KEY}" -ge 16 ] || fail "API_KEY must be at least 16 characters"
  case "$API_KEY" in
    *' '*) fail "API_KEY must not contain spaces; it is sent verbatim as a bearer token" ;;
  esac
else
  log "WARNING: TEI_ALLOW_PUBLIC=true. No API key is set and anyone who reaches this URL can run embeddings on this instance."
fi

# Railway mounts volumes owned by root and this image runs as root, so there is nothing to chown --
# but the directory has to exist before the router tries to write into it.
mkdir -p "$HUGGINGFACE_HUB_CACHE" || fail "cannot create the model cache at $HUGGINGFACE_HUB_CACHE"

log "model ${MODEL_ID}, cache ${HUGGINGFACE_HUB_CACHE}, listening on ${HOSTNAME}:${PUBLIC_PORT}"
if [ "$ALLOW_PUBLIC" != "true" ]; then
  log "API key required for every route except /health, /, /ping and /metrics (key length ${#API_KEY})"
fi

export MODEL_ID HUGGINGFACE_HUB_CACHE HOSTNAME PORT="$PUBLIC_PORT" PROMETHEUS_PORT

# The router prints its parsed arguments at INFO on every start, and `api_key` is not one of the
# fields it redacts:
#
#   Args { ... api_key: Some("the-actual-key") ... }
#
# On a hosting platform that puts the credential into the deploy log, where it is readable by anyone
# with project access and kept for as long as logs are kept. The wrapper filters the router's output
# through sed so the key never reaches the platform's log collector.
#
# The pattern is handed to sed on a pipe rather than on its command line, so the key does not appear
# in any process's arguments either. `exec` keeps the redirections, so the router still receives
# signals directly and the container's exit status is still its own.
if [ "$ALLOW_PUBLIC" != "true" ]; then
  redact() { printf 's|%s|***REDACTED***|g\n' "$API_KEY"; }
  exec > >(sed -u -f <(redact)) 2> >(sed -u -f <(redact) >&2)
fi

# The router handles SIGTERM itself and exits promptly, so exec is safe here.
exec text-embeddings-router --json-output "$@"
