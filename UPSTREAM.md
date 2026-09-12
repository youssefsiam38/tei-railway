# Upstream provenance

## Text Embeddings Inference

| | |
|---|---|
| Project | https://github.com/huggingface/text-embeddings-inference |
| Licence | Apache-2.0 (`LICENSE`) |
| Version pinned | 1.8 |
| Image | `ghcr.io/huggingface/text-embeddings-inference:cpu-1.8` |
| Digest | `sha256:8de25e75ce39617f17f2f6c77d60a4f75b65e779ed5005420eb1400072a15c1c` |
| Architecture | linux/amd64 |

The CPU image is used. Upstream also publishes CUDA builds for several GPU architectures, which
need hardware Railway does not sell on standard plans; a static check in `tests/static.sh` fails if
one is ever pinned here. There is a separate arm64 build; this template has not tested it and
publishes amd64 only, which is what Railway runs.

The image is small for this family, about 230 MB compressed, because the router is a Rust binary and
the model is downloaded at runtime rather than baked in.

## What this repository changes

It adds three things and removes none:

1. `scripts/entrypoint.sh` as the image entrypoint, which still `exec`s `text-embeddings-router`.
2. Two environment defaults: `MODEL_ID` (upstream has none, and the router will not start without
   one) and `HOSTNAME=0.0.0.0`. The cache path is left at upstream's own `/data`.
3. The upstream licence at `/usr/share/licenses/tei-railway/`.

No Rust file is patched, no route is added or rewritten, and no dependency is changed. The image's
own `PORT=80` default is left alone.

## Licence obligations

Apache-2.0 requires the licence and notices to travel with the software. It is vendored in
`licenses/` and copied into the image. `THIRD_PARTY_NOTICES.md` records what is shipped.

The wrapper itself is MIT. Redistributing the wrapper image redistributes the upstream image, which
is why the notice is inside it rather than only in this repository.

## Bumping the upstream version

1. Read the upstream release notes, and **re-read `router/src/http/server.rs` for the split between
   `routes` and `public_routes`.** That split is the reason this template needs no proxy; if a route
   that does work moves into the public set, or a probe route moves out, the template's design
   assumption changes.
2. Resolve the new digest:
   `docker buildx imagetools inspect ghcr.io/huggingface/text-embeddings-inference:cpu-X.Y`
3. Update `TEI_IMAGE` and `TEI_VERSION` in the Dockerfile and the assertion in `tests/static.sh`,
   which pins the tag string.
4. Run the full suite locally, then tag a release. CI rebuilds, retests against the candidate image
   and pushes.
