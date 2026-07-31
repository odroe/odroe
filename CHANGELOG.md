# Changelog

## Unreleased

- Add typed SQL, typed inner and left joins, and SQLite, PostgreSQL,
  MySQL/MariaDB, and Cloudflare D1 entrypoints.
- Preserve the dialect on typed `BoundSql` statements and reject explicit
  driver mismatches before statement I/O. Handwritten statements remain
  unpinned unless `dialect` is supplied.
- Add request invocation lifetimes and a Fetch adapter for local
  Cloudflare Workers builds.
- Add optional stable `ServerFunction.id` wire identifiers, reject empty,
  non-literal, and duplicate IDs in file routes, and preserve the existing
  path-and-variable fallback when an ID is omitted.
- Add a per-request asynchronous RPC `headersProvider`, keep protocol headers
  framework-owned, and classify non-protocol HTTP failures by status instead
  of leaking JSON parsing errors.
- Add preflight-safe RPC cancellation across asynchronous headers, request
  bodies, response setup, typed value bodies, and streams, with direct Query
  cancellation bridging and no automatic timeout or retry policy.
- Limit typed RPC responses to 1 MiB per value or stream frame by default,
  before UTF-8 decoding. Applications can configure
  `RpcClient.maxResponseFrameBytes` or `RpcModule.http`, while cumulative
  stream size and explicit `ServerResponse` bodies remain caller-owned.
- Limit server-generated typed response frames to 1 MiB by default, encode
  them directly into bounded UTF-8 output, and expose request and response
  budgets through generated `createServer`. Oversized values return a bounded
  500 error frame; oversized stream items terminate with one bounded error.
- Make the default HTTP transport's 10 MiB pre-send request body buffer
  configurable through `HttpTransport` and `RpcModule.http`, export
  `PayloadTooLargeException` from `rpc.dart`, and keep content framing owned by
  the transport.
- Report unexpected module, request execution, RPC encoding, and response
  stream failures through configurable `Server.onError`, with a dependency-free
  Zone logger by default. Module setup failures remain rethrown, request and
  stream outcomes remain unchanged, and synchronous or asynchronous reporter
  failures cannot replace the original outcome. Malformed server-function
  inputs remain controlled HTTP 400 results instead of producing error logs.
- Make application context, route capability, and request context keys
  identity-based so independent modules cannot collide through equal constant
  type/name pairs.
  This is source-breaking: replace `const ContextKey(...)`,
  `const RouteCapability(...)`, and `const RequestKey(...)` declarations with
  one shared top-level `final` instance per key, then reuse it at every
  provider and consumer. Registration now uses
  `key.provide(registry, value)` or
  `key.provideFactory(registry, create)`; optional route values use
  `key.attach(route, value)`; request values use `key.set(context, value)`.
  These key-first instance methods reject incompatible values both statically
  and through widened generic views at runtime.
- Add Press collections, dynamic prerender locations, and the Odroe-built
  documentation website.
- Change prerender defaults to fixed concurrency 4, at most 1000 routes and
  1 MiB per HTML response. Link crawling is now opt-in with
  `--prerender-crawl` or `crawlLinks: true`; raise the matching CLI or SDK
  limits for larger applications. SDK seed routes must be absolute local paths
  without queries or fragments.
- Resolve application prerender locations before compilation, preserve the
  previous document-only output until a replacement succeeds, and avoid
  duplicate native compilation for Cloudflare builds.
- Revalidate native static assets with weak ETags and Last-Modified, stream
  eligible responses with optional gzip, reject ambiguous or escaped paths on
  every request, serve prerendered indexes at canonical routes with
  media-quality negotiation, and stop inferring immutable caching from
  filenames.
- Mount source `public/` assets during development while isolating prerender
  and development server-only runs from stale Flutter origins and static build
  output.
- Release unread Fetch request bodies, return 501 consistently for unsupported
  methods, and keep normal IO response completion distinct from cancellation.
- Freeze server, route, and server-function configuration snapshots and include
  the required Allow header in 405 route responses.
