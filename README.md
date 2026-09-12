# Text Embeddings Inference on Railway

A community Railway template for [Text Embeddings Inference][upstream], Hugging Face's server for
embedding and reranking models. Send it text over HTTP and it returns vectors, fast, on a CPU, with
no per-token bill and nothing leaving your instance. It speaks both its own API and OpenAI's
`/v1/embeddings`, so most clients work unchanged. It is not affiliated with Hugging Face.

Upstream's help text states the problem plainly: "By default the server responds to every request."
The `--api-key` option exists and is unset unless you set it, so a deployment on a public hostname
is an open embeddings endpoint running on your CPU and your bill.

What upstream gets right is the route split: `/health`, `/`, `/ping` and `/metrics` are public so an
orchestrator can probe them, and everything that does work sits behind the key. This wrapper adds no
proxy. It refuses to start until the key is set, puts the model cache where a volume can hold it,
and leaves the application exactly as published.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/text-embeddings-inference)

## What you get

- The official upstream CPU image, pinned by tag and digest.
- A key you never have to invent: the template generates one.
- A persistent volume for the model, so a redeploy does not download it again.
- Fail-fast validation: the container refuses to start with a missing key, a key under sixteen
  characters, a key containing spaces, an empty model, or a port that collides with the metrics
  listener.
- **The key kept out of your deploy log.** Upstream prints its parsed arguments on every start and
  does not redact `api_key`, so a stock container writes the credential into the platform's logs.
  The wrapper filters it out.

## First run

1. Deploy the template. Railway generates `API_KEY` for you.
2. Copy that value out of the service variables.
3. Embed something:

```bash
curl -H "Authorization: Bearer YOUR_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"inputs": ["a sentence about railways"]}' \
     https://YOUR-DOMAIN/embed
```

Or point an OpenAI client at `https://YOUR-DOMAIN/v1` with that key as its API key.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `API_KEY` | none, required | Bearer token for every route that does work. At least 16 characters, no spaces. |
| `TEI_ALLOW_PUBLIC` | `false` | `true` runs with no key at all. Read `SECURITY.md` first. |
| `MODEL_ID` | `BAAI/bge-small-en-v1.5` | Any embedding or reranking model on the Hub that this backend supports. |
| `PORT` | set by Railway | Port the API listens on. Railway probes its healthcheck against it. |
| `PROMETHEUS_PORT` | `9000` | Second listener for metrics. Must differ from `PORT`. |
| `PAYLOAD_LIMIT` | `2000000` | Largest accepted request body, in bytes. |
| `HF_TOKEN` | unset | Needed only for a gated or private model. |
| `MAX_CLIENT_BATCH_SIZE`, `AUTO_TRUNCATE`, `DTYPE`, `POOLING`, `REVISION` | upstream's | Passed through untouched. |

## Choosing a model

The default is small, fast and English. Anything the backend supports works, but a bigger model
means a longer first start and more memory:

| Model | Dimensions | Rough size | Good for |
|---|---:|---:|---|
| `BAAI/bge-small-en-v1.5` | 384 | 130 MB | The default. English, quick. |
| `BAAI/bge-base-en-v1.5` | 768 | 440 MB | English, more accurate. |
| `intfloat/multilingual-e5-small` | 384 | 470 MB | Many languages. |
| `BAAI/bge-reranker-base` | — | 1.1 GB | Reranking through `/rerank`, not embeddings. |

## Persistent paths

| Path | Holds |
|---|---|
| `/data` | The Hugging Face model cache. |

Nothing else survives a restart. This service stores no text: it takes input, returns vectors, and
writes neither to disk.

## Local development

```bash
docker compose build
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

`tests/railway-smoke.sh https://your-domain` checks a deployed instance; set `KEY_FILE` to a file
holding the API key to exercise the authenticated paths too.

## Documentation

| File | Covers |
|---|---|
| `ARCHITECTURE.md` | Service graph, the route split, boot sequence, ports, health. |
| `SECURITY.md` | What the key covers, what stays open, and how to rotate it. |
| `UPSTREAM.md` | Provenance, what the wrapper changes, how to bump the version. |
| `MAINTENANCE.md` | Release process, what to watch, rollback. |
| `THIRD_PARTY_NOTICES.md` | Licences shipped in the image. |
| `MARKETPLACE_AUDIT.md` | Why this template exists. |
| `RAILWAY_TEMPLATE.md` | The exact published template configuration. |

## Licence

The wrapper is MIT. Text Embeddings Inference is Apache-2.0, and its licence travels inside the
image at `/usr/share/licenses/tei-railway/`.

[upstream]: https://github.com/huggingface/text-embeddings-inference
