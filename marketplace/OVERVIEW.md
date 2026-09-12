# Deploy and Host Text Embeddings Inference on Railway

Text Embeddings Inference turns text into vectors. Send it a sentence, a paragraph or a batch of
documents over HTTP and it returns the embeddings a search index or a retrieval pipeline needs. It
runs the model on your own instance, so there is no per-token bill and the text does not leave your
infrastructure. It also speaks OpenAI's `/v1/embeddings`, so most clients work without changes. This
is a community-maintained template; it is not affiliated with Hugging Face.

## About Hosting Text Embeddings Inference

It is the lightest service of its kind to host: a single Rust binary, no database, no queue, no
interpreter. The only state is the model, which is downloaded on the first start and kept on a
volume, so later deploys start in seconds.

The one thing that needs care is the key. Upstream's own documentation says the server "responds to
every request" unless an API key is set, and nothing sets it for you. On a platform that gives every
service a public address the moment it deploys, that means an open endpoint running on your CPU.
What upstream gets right is which routes the key covers: the health and metrics probes stay open so
a platform can watch the service, and everything that does work needs the token. This template
generates the key, requires it, and refuses to start without one.

## Why Deploy Text Embeddings Inference on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Text Embeddings Inference on Railway, you are one step closer to supporting a complete
full-stack application with minimal burden. Host your servers, databases, AI agents, and more on
Railway.

Concretely, this template generates the API key, picks a small fast model so the first start is
quick, attaches the volume that caches it, pins the listening port to the generated domain, keeps it
clear of the metrics listener, and points the healthcheck at the one route that answers without a
token.

## Common Use Cases

- Build the embedding half of a retrieval pipeline next to the vector database that stores it.
- Give an application semantic search over its own content without sending that content to an API.
- Rerank search results with a cross-encoder through the same service.
- Replace a hosted embeddings API in an existing client by changing one base URL.

## Dependencies for Text Embeddings Inference Hosting

- A persistent volume for the model cache, so a redeploy does not download it again.
- Enough memory for the chosen model. The default is small; a reranker or a multilingual model needs
  more.
- A Hugging Face token only if you choose a gated or private model.
- Nothing else. No external database, cache or queue.

### Deployment Dependencies

- Text Embeddings Inference upstream project: https://github.com/huggingface/text-embeddings-inference
- The default model, BAAI/bge-small-en-v1.5: https://huggingface.co/BAAI/bge-small-en-v1.5
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/tei-railway
- Published image: `ghcr.io/youssefsiam38/tei-railway`
- The upstream project is Apache-2.0 licensed, which is permissive.

### Implementation Details

The wrapper adds no application code and no proxy, because upstream already exempts the right routes
from its key check. It validates the configuration and refuses to start on a missing key, a key
shorter than sixteen characters, a key containing spaces, an empty model name, or a port that
collides with the metrics listener. It also filters the key out of the application's own start-up
log, which prints every parsed argument and does not redact that one, so the credential does not end
up in the platform's deploy log. It creates the cache directory the volume mounts over and then
hands control to the router directly, so stop signals reach the application and the container's exit
status is the application's own.
