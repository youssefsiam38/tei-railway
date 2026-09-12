# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Text Embeddings Inference |
| Code | `text-embeddings-inference` |
| Template id | `dc6e6823-be56-488d-bece-2f832ec4adcb` |
| Category | AI/ML |
| Image | `ghcr.io/youssefsiam38/tei-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Service `tei` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/tei-railway:<version>` |
| Port | 3000 |
| Domain | generated, target port 3000 |
| Healthcheck | `/health` |
| Volume | `/data` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `API_KEY` | `${{secret(32)}}` |
| `MODEL_ID` | `BAAI/bge-small-en-v1.5` |
| `PORT` | `3000` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `600` |

## Notes

- Every variable has a value or a generator, so a headless deploy works without a TTY.
- **The healthcheck path must be `/health`.** Everything else that answers usefully needs the bearer
  token, which the platform does not have.
- **The healthcheck timeout is raised with a variable, not a template field.** A generated template
  carries `healthcheckPath` but no timeout, so the template sets
  `RAILWAY_HEALTHCHECK_TIMEOUT_SEC=600`. The first start downloads the model.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the value
  of `PORT`, and the router reads the same variable, so there is nothing to translate. Do not set it
  to 9000, which is the metrics listener; the wrapper refuses that.
- The upstream image bakes `PORT=80` as its own default. The template's value overrides it.
- The volume must mount `/data`, which is upstream's own cache path. Without it the model is
  re-downloaded on every deploy.
- Choosing a larger `MODEL_ID` means a longer first start and more memory. `SECURITY.md` and the
  README list the practical options.
- There is no second service and nothing on the private network.
