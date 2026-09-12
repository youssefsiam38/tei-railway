#!/usr/bin/env bash
# shellcheck disable=SC2015
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "shell syntax"
for f in scripts/*.sh tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s bash scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config >/dev/null; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
df=$(cat Dockerfile)
assert_contains "upstream pinned by tag and digest" 'text-embeddings-inference:cpu-1.8@sha256:' "$df"
assert_contains "entrypoint is the wrapper" 'ENTRYPOINT \["/usr/local/bin/tei-railway-entrypoint"\]' "$df"
assert_contains "a small CPU model is the default" 'MODEL_ID=BAAI/bge-small-en-v1.5' "$df"
# The CUDA images need hardware Railway does not sell on standard plans.
if grep -E '^ARG TEI_IMAGE=' Dockerfile | grep -qE ':(cuda|turing|ampere|hopper|89|86|90)'; then
  fail "a GPU image is pinned; Railway has no GPU on standard plans"
else
  pass "the CPU image is pinned"
fi
if grep -qE '^\s+PORT=' Dockerfile; then fail "PORT must not be baked in; it would shadow the platform's PORT"; else pass "public port left to the platform"; fi
if grep -qE '^\s+API_KEY=' Dockerfile; then fail "an API key is baked into the image"; else pass "no API key in the image"; fi

section "the key cannot be forgotten"
ep=$(cat scripts/entrypoint.sh)
assert_contains "requires an API key unless explicitly opted out" 'missing required variable: API_KEY' "$ep"
assert_contains "states the length rule" 'at least 16 characters' "$ep"
assert_contains "rejects a key with spaces" 'sent verbatim as a bearer token' "$ep"
assert_contains "refuses a metrics port collision" 'cannot share a port' "$ep"
assert_contains "the opt-out is loud" 'TEI_ALLOW_PUBLIC=true. No API key is set' "$ep"
# The router prints its parsed arguments, api_key among them, on every start.
assert_contains "the router's output is filtered for the key" 'REDACTED' "$ep"
# shellcheck disable=SC2016  # a literal pattern to search for, not an expansion
if grep -qE 'sed .*"[$]API_KEY"' scripts/entrypoint.sh; then
  fail "the key is passed to sed on a command line, where a process listing would show it"
else
  pass "the redaction pattern never reaches a command line"
fi
# Railway colours a log line by the stream it arrived on, so routine start-up messages written to
# stderr are shown to the deployer as errors.
if grep -q '^log()' scripts/entrypoint.sh && ! grep '^log()' scripts/entrypoint.sh | grep -q '>&2'; then
  pass "routine logs go to stdout"
else
  fail "log() writes to stderr; Railway would show every start-up line as an error"
fi
if grep '^fail()' scripts/entrypoint.sh | grep -q '>&2'; then
  pass "failures go to stderr"
else
  fail "fail() does not write to stderr"
fi
# The router handles SIGTERM itself, so exec keeps the container's exit status honest.
if grep -q '^exec text-embeddings-router' scripts/entrypoint.sh; then
  pass "the router is exec-ed so signals reach it directly"
else
  fail "the router is not exec-ed"
fi

section "workflows"
# a stale image-override name from a copied workflow makes CI test the wrong image, and the failure
# looks like a missing local build rather than a configuration mistake
override=$(grep -oE '[A-Z_]*_RAILWAY_IMAGE' compose.yaml | head -1)
for wf in .github/workflows/*.yml; do
  if grep -q 'candidate' "$wf" && ! grep -q "$override" "$wf"; then
    fail "$wf tests a candidate image but never sets $override"
  else
    pass "image override name matches compose in $wf"
  fi
done
for wf in .github/workflows/*.yml; do
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: .*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|xox[baprs]-|hf_[A-Za-z0-9]{30,})' -- . >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
