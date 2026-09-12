# syntax=docker/dockerfile:1
#
# tei-railway: thin wrapper around Hugging Face's Text Embeddings Inference CPU image.
#
# Upstream's own help text is the whole problem in one sentence: "By default the server responds to
# every request." `--api-key` exists and is unset unless you pass it, so a deployment on a public
# hostname is an open embeddings endpoint that anyone can send text to, on the deployer's CPU.
#
# The route split upstream already has is the right one -- `/health`, `/`, `/ping` and `/metrics`
# are public, and everything that does work sits behind the key -- so this wrapper adds no proxy.
# It refuses to start until the key is set, puts the model cache somewhere a volume can hold it,
# and leaves the application exactly as published.
ARG TEI_IMAGE=ghcr.io/huggingface/text-embeddings-inference:cpu-1.8@sha256:8de25e75ce39617f17f2f6c77d60a4f75b65e779ed5005420eb1400072a15c1c

FROM ${TEI_IMAGE}

ARG TEI_VERSION=1.8
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

COPY licenses/ /usr/share/licenses/tei-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/tei-railway-entrypoint

# The model is downloaded on the first start into the cache, which is where the Railway volume
# mounts, so a redeploy reuses it instead of fetching it again. The cache path is upstream's own
# default of /data; only the model and the listen address are set here.
ENV MODEL_ID=BAAI/bge-small-en-v1.5 \
    HOSTNAME=0.0.0.0

LABEL org.opencontainers.image.title="tei-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Text Embeddings Inference, a self-hosted embeddings and reranking API. Requires the API key upstream leaves off. Not affiliated with Hugging Face." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/tei-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/tei-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/tei-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="ghcr.io/huggingface/text-embeddings-inference:cpu-${TEI_VERSION}" \
      io.tei-railway.upstream.version="${TEI_VERSION}"

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/tei-railway-entrypoint"]
