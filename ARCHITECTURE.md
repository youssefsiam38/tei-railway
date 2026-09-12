# Architecture

## Service graph

One service, one volume. There is no proxy, no database and nothing on the private network.

```
internet --> Railway edge (TLS) --> :PORT  text-embeddings-router
                                              |
                                              +-- /data (volume)  the Hugging Face model cache
```

## Why a wrapper image, and why no proxy

Every other template in this family that fronts an unauthenticated application puts Caddy in front
of it. This one does not, because upstream has already drawn the line in the right place.
`router/src/http/server.rs` builds two routers:

```rust
let mut routes = Router::new()
    .route("/info", get(get_model_info))
    .route("/embed", post(embed))
    ...
    .route("/v1/embeddings", post(openai_embed));

let mut public_routes = Router::new()
    .route("/health", get(health))
    .route("/", get(health))
    .route("/ping", get(health))
    .route("/metrics", get(metrics));
```

and applies the bearer-token middleware to the first only. Health probes work without a credential,
which a platform needs, and everything that costs CPU needs one.

The single thing upstream leaves to the operator is whether the key exists at all. From its own
help text: "By default the server responds to every request." That is the wrapper's entire job, so
the wrapper is small: validate, create the cache directory, `exec` the router.

Adding a proxy here would cost a second process and a second hop and buy nothing, since the routes
that matter are already behind a check.

## Boot sequence

1. Validate the environment. Names of missing or wrong variables are printed; values never are.
2. Refuse to continue without an API key, unless `TEI_ALLOW_PUBLIC=true` is set deliberately.
3. Create the model cache directory, which the volume mounts over.
4. Redirect the router's output through `sed`, which replaces the API key with `***REDACTED***`.
   The router prints its parsed arguments on every start and does not redact `api_key`, so without
   this the credential lands in the platform's deploy log. The pattern reaches `sed` on a pipe, not
   on its command line.
5. `exec` `text-embeddings-router --json-output`. The router handles SIGTERM itself and exits
   promptly, so `exec` is right here: the signal reaches it directly and the container's exit status
   is the router's own. `exec` keeps the redirections from the previous step.

The first start downloads the model from the Hugging Face hub into the cache. For the default model
that is about 130 MB; for a reranker it can be over a gigabyte.

## Ports

| Port | Listener | Reachable from |
|---|---|---|
| `PORT` | the API | the internet |
| `PROMETHEUS_PORT` (9000) | metrics | inside the container only, unless a domain is pointed at it |

The router reads `PORT` itself, so there is nothing to translate; the entrypoint only checks that it
is a number and that it does not collide with the metrics listener. Railway runs its healthcheck
against `PORT`, so it must match the domain's target port.

Note that the upstream image bakes `PORT=80` as its own default. The template sets `PORT` explicitly,
which overrides it; a bare `docker run` with no `PORT` listens on 80.

## Health

`/health` is the healthcheck path. It answers without a credential by upstream's design, returns no
body worth reading, and reports the model backend's real state rather than just that the process is
alive.

## State

The model cache under `/data` is the only durable state. No request is written to disk: text goes
in, vectors come back, and a restart loses nothing but the cache, which is re-downloadable.
