# Maintenance

## Release process

1. Make the change on a branch. The `test` workflow runs the full suite on every push and pull
   request.
2. Run locally:
   ```bash
   docker compose build --pull
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. Tag `vX.Y.Z`. The `publish-image` workflow builds an amd64 candidate, runs the smoke and
   persistence suites against that exact image, and only then pushes it to GHCR as `X.Y.Z`, `X.Y`
   and `latest`.
4. Update the Railway template to the new tag. `RAILWAY_TEMPLATE.md` records the exact
   configuration; the template pins a version tag, never a digest, because the template generator
   rejects `@sha256:` references.
5. Deploy the updated template into a scratch project and run
   `tests/railway-smoke.sh https://domain` against it before leaving it published.

## What to watch

| Source | Why |
|---|---|
| https://github.com/huggingface/text-embeddings-inference/releases | New versions and new backends. |
| That repository's `router/src/http/server.rs` | **The `routes` / `public_routes` split is this template's entire security model.** A route moving between them changes what the key covers. |
| That repository's `router/src/main.rs` | The clap definitions are the environment variable names; a renamed field renames the variable. |
| Railway's healthcheck behaviour | The probe runs against `PORT`; a platform change there breaks every template in this family at once. |

## Breaking-change checklist

Before bumping the upstream digest, confirm:

- [ ] `text-embeddings-router` is still the binary name and still reads `MODEL_ID`, `PORT`,
      `HOSTNAME`, `API_KEY` and `HUGGINGFACE_HUB_CACHE` from the environment.
- [ ] `/health`, `/`, `/ping` and `/metrics` are still public, and nothing else is.
- [ ] `/embed` still takes `{"inputs": [...]}` and returns a list of lists of floats.
- [ ] `/v1/embeddings` still returns `{"object": "list", "data": [{"embedding": [...]}]}`.
- [ ] `/info` still reports `model_id` and `model_type`.
- [ ] The hub cache still lands under `HUGGINGFACE_HUB_CACHE` as `models--<org>--<name>`, since a
      persistence test asserts that directory name.
- [ ] The default model still returns 384 dimensions, or the smoke test's dimension assertion moves
      with it.

## Rolling back

Republish the template with the previous wrapper tag. The only state is a re-downloadable model
cache, so a rollback is a tag change and a redeploy with nothing to migrate.

## If this repository is abandoned

The image is a thin wrapper: the Dockerfile, the entrypoint and the tests are the whole of it. Fork
it, change the `org.opencontainers.image.source` label and the GHCR path, and publish your own
template. Nothing in the design depends on this account.
