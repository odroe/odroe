# Changelog

## Unreleased

- Require exactly one encoded function ID segment under the RPC namespace,
  preserving `%2F` inside IDs while rejecting empty or extra path segments
  before a function can run. Validate and canonicalize custom function paths
  consistently on clients and servers.
- Add `odroe init --full-stack` as an atomic user-project starter spanning
  Flutter, Query, typed RPC, Server, typed SQL, native SQLite, and Cloudflare
  D1. Preserve the small default starter, allow untouched starters to upgrade,
  and reject custom files, unsafe paths, or partial writes without `--force`.
- Make the full-stack reference application's local Cloudflare path
  reproducible with its own locked Wrangler toolchain, Node and npm engine
  gates, D1 migration and development scripts, and a direct Getting Started
  handoff.
  Keep installed Node and Wrangler state out of the Dart publication archive.
- Keep the full-stack reference application product-focused by removing
  uncalled demonstration RPCs, including a custom `PostId` function that had
  no registered serialization adapter. Preserve stream, collection, and
  prefixed custom-type generation coverage in compiler tests instead.
- Make `server.dart` the complete server product entrypoint. Move
  `ServerFunction`, `ServerFunctionBinding`, `ServerFunctionContext`, and
  `ServerFunctionHandler` out of `rpc.dart`; server files now import
  `server.dart`, while `rpc.dart` keeps client/shared protocol APIs including
  `NoServerInput` and `ValueDecoder`.
- Run the example post page through Flutter Query, generated typed RPC, a real
  `DatabaseModule`, typed SQL, native SQLite, and local Cloudflare D1. Keep the
  drivers platform-isolated, track the D1 schema as a migration, and export
  `NotFound` and `Redirect` from the RPC product entrypoint. Validate typed
  frame versions, reject empty typed responses, and require control-frame
  status to match HTTP status. Raise the minimum server frame budget from 16
  to 28 bytes so even the terminal fallback carries `version: 1`.
- Let routed Flutter apps select path or hash URLs explicitly from `App` before
  `runApp`, including when a lazy module iterable yields the Router later,
  while preserving the host's URL strategy by default. Reject stale prerender
  handoff when the live browser pathname or search differs, preserving typed
  search during JavaScript and WebAssembly startup.
- Export the PostgreSQL connection and pool types plus the HTTP client required
  by Odroe's own public driver and transport constructors.
- Pin the documentation site's Wrangler deployment tool, add a no-upload
  dry-run gate, and document authorized deploy, version readback, and HTTP
  smoke checks.
- Select browser DOM handoff and external navigation through JS interop so
  Flutter Web keeps the same behavior in JavaScript and WebAssembly builds.
- Freeze nested `QueryKey` list and map parts at construction so cache,
  hydration, and persistence identities cannot diverge after caller mutation.
- Cancel destroyed mutations while they are paused for connectivity or serial
  scope, release their wait listeners, and keep `QueryClient.clear()` safe.
- Return current state from unsubscribed manual refetches and let interval
  polling reuse active work instead of repeatedly cancelling slow requests.
- Add typed SQL, typed inner and left joins, and SQLite, PostgreSQL,
  MySQL/MariaDB, and Cloudflare D1 entrypoints.
- Preserve the dialect on typed `BoundSql` statements and reject explicit
  driver mismatches before statement I/O. Handwritten statements remain
  unpinned unless `dialect` is supplied.
- Add request invocation lifetimes and a Fetch adapter for local
  Cloudflare Workers builds.
- Serialize completed and pending Query handoff state through the application
  `Serializer`, so built-in and custom values round-trip through Document SSR
  instead of failing during JSON encoding.
- Add optional stable `ServerFunction.id` wire identifiers, reject empty,
  non-literal, and duplicate IDs in file routes, and preserve the existing
  path-and-variable fallback when an ID is omitted.
- Add a per-request asynchronous RPC `headersProvider`, keep protocol headers
  framework-owned, and classify non-protocol HTTP failures by status instead
  of leaking JSON parsing errors.
- Reject non-HTTP(S), hostless, and credential-bearing `RpcModule.http`
  base URIs during setup, while keeping omitted URIs for same-origin Web RPC.
  Cross-platform examples now require an explicit native API origin.
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
- Reuse `Server.onError` from the generated native bootstrap for IO-owned
  static, development-proxy, response-metadata, framing, and raw omitted-body
  failures without duplicating handler or source-stream reports. Metadata
  failures now discard partially applied status, reason, headers, cookies, and
  content framing before returning a fixed 500; for a supported method,
  malformed forwarded authority remains a controlled 400 before static or
  proxy dispatch. Bodyless framing is now status-aware: 1xx and 204 omit
  `Content-Length` and `Transfer-Encoding`, 205 emits zero length, and HEAD
  preserves representation framing only where the protocol permits it.
- Reuse `Server.onError` from the generated Fetch bootstrap for adapter-owned
  response metadata, construction, and byte-conversion failures. Keep handler
  and source-stream reporting Server-owned, register asynchronous reporters
  with host `waitUntil`, and document Cloudflare's `enable_request_signal`
  flag for real incoming-client cancellation.
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
- Let `build --no-server` prerender through the generated Dart server source
  without emitting an unused native or Cloudflare artifact, so assets-only
  deployments and their tests avoid deployment-only compilation.
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
