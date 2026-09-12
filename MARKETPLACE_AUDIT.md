# Marketplace audit

Checked 2026-09-12 against Railway's template search.

## Gap

`templateSearch` returns no template named after Text Embeddings Inference, and none of the loose
matches serves a dedicated embeddings API. What exists nearby solves an adjacent problem:

| Existing template | Deploys | What it is | Why it does not cover this |
|---|---:|---|---|
| Ollama, and an "Ollama — Private LLM & Embeddings API" variant | 468, 7 | A local LLM server that can also embed | A general inference server; embeddings are a side feature, and it carries a chat model's footprint to do them. |
| Qdrant, ChromaDB, Weaviate | 46-325 | Vector databases | They store vectors. Something has to make them. |
| Xinference | 1 | A multi-model inference framework | Much heavier, and aimed at serving many model types. |
| LiteLLM, Bifrost, Portkey | 18-110 | Gateways to hosted model APIs | They forward to somebody else's embeddings, with somebody else's bill. |

The shape that is missing is the small, fast, dedicated one: a service whose whole job is turning
text into vectors, next to the vector database that stores them.

## Why Text Embeddings Inference

- Apache-2.0, so redistributing a wrapper image is unencumbered.
- 5,048 stars and a release four days before this audit.
- The CPU image is about 230 MB compressed, the smallest upstream in this family, and the model is
  a separate download rather than a baked layer.
- A Rust binary with no interpreter, no database and no queue: it starts in seconds once the model
  is cached.
- It speaks OpenAI's `/v1/embeddings` as well as its own API, so it drops into existing clients.
- It is the natural companion to the vector databases that are already popular on the marketplace,
  which is what makes the gap worth filling rather than merely real.

## Why it needs a template rather than a raw image

Deploying `ghcr.io/huggingface/text-embeddings-inference:cpu-1.8` directly gives a service that, in
upstream's own words, "responds to every request". The key exists; nothing sets it. On a public
hostname that is an open endpoint running on the deployer's CPU.

The template also settles three things that are easy to get wrong:

1. **`MODEL_ID` has no default.** The router will not start without one, and a first-time deployer
   has no reason to know which small model to name.
2. **The volume.** Without one the model is downloaded again on every deploy, turning a redeploy
   into a multi-minute outage for no reason.
3. **The metrics port.** A second listener defaults to 9000; pointing `PORT` there produces a
   confusing bind failure rather than a clear message.

## Category

AI/ML. Railway added that category after the earlier templates in this family were published, and it
is the right home for an inference service.
