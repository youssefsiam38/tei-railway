# Third-party notices

This image redistributes software written by other people. Its licence is shipped inside the image
at `/usr/share/licenses/tei-railway/` and vendored in `licenses/` here.

## Shipped inside the wrapper image

| Component | Licence | Source | Notice |
|---|---|---|---|
| Text Embeddings Inference 1.8 | Apache-2.0 | https://github.com/huggingface/text-embeddings-inference | `licenses/TEI-LICENSE` |

The upstream image itself contains further components, among them the Candle and ONNX Runtime
inference backends, the Hugging Face tokenizers library, Axum and Tokio (all MIT or Apache-2.0), and
Intel's MKL runtime shim. Their notices travel in the layers upstream publishes; this wrapper does
not repackage or relink any of them.

Models are not shipped. They are downloaded at runtime from the Hugging Face hub and are covered by
their own licences, which differ by model. The default, `BAAI/bge-small-en-v1.5`, is MIT.

## Licence obligations

Apache-2.0 requires that the licence, the copyright notice and any NOTICE file accompany the
software, and that modified files be marked. No upstream file is modified here; the wrapper adds an
entrypoint alongside them. Copying the licence into the image satisfies the notice requirement for
anyone who pulls the image without reading this repository.

## Trademarks and artwork

"Hugging Face" is a mark of Hugging Face, Inc., which is not affiliated with and does not endorse
this template. The template icon in `assets/` was made for this repository and is not an upstream
logo.

## This repository

The wrapper, its entrypoint, its tests and its documentation are MIT licensed. See `LICENSE`.
