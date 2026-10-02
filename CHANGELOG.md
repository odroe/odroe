# Changelog

## Unreleased

- Integrate the existing full-stack platform in one batch from the prior
  development branch, retaining public-main prerender ownership, real-path
  protection, recovery diagnostics, and HTTP configuration validation. Preserve
  relative client RPC namespaces while keeping server namespaces absolute;
  reject invalid paths before constructing an owned HTTP client. Keep
  `ODROE_RPC_ORIGIN` as the starter's public native-client configuration name.
  This source integration does not publish a new hosted version or establish
  signed mobile, remote database, or Cloudflare deployment support.

- Publish Native full-stack builds as one complete, rollback-safe artifact.
  Odroe now keeps the AOT server staged through Flutter Web compilation and
  prerendering, layers the actual Flutter and static outputs into
  `<bundle>/build/web`, then replaces the owned bundle once. A failed client
  build or prerender leaves the previous server and client together;
  `--server-only` deliberately omits Web output instead of carrying stale
  assets forward. Flutter and prerender roots may match or remain disjoint,
  but newly rejected nested roots no longer produce ambiguous artifact trees.
  Odroe-managed Flutter Web output must now resolve inside the project
  `build/` tree; each build uses a clean sibling stage and atomically replaces
  that output so removed routes and assets cannot survive a rebuild.
- Generate symmetric typed RPC codecs for project-local enums, including
  direct values, non-generic aliases, nullable values, collections, named
  records, and stream items. Enum cases cross the wire by declaration name;
  unknown input fails with HTTP 400 before the handler, while invalid output is
  normalized to `RpcProtocolException`. This generated path takes precedence
  over `SerializationAdapter` for directly declared project enums; dependency
  and otherwise opaque nominal values remain adapter-owned. Renaming or
  removing a shipped enum case is a breaking wire change.
- Make owned Native bundles resolve their runtime root from the compiled
  executable before application creation. A validated bundle marker now makes
  relative SQLite, migration, static, and application resource paths independent
  of the caller's working directory, while source and development runs keep the
  caller-selected project directory. CLI-managed prerender also keeps the
  project directory for build-time source resources. Reject a missing,
  non-regular, or damaged marker in compiled bundles before touching application
  state.
- Initialize `odroe create` starters in the current CLI process after dependency
  resolution and canonical checkout identity validation. Keep only Flutter
  scaffold creation and dependency resolution as child processes, avoiding a
  redundant Dart startup and native build-hook cost while preserving staged
  rollback, interruption handling, and no-replace publication. Commit buffered
  initializer output only after publication, using the final project path.
- Enable and verify SQLite foreign-key enforcement whenever a native in-memory
  or file connection opens. Reject a connection that cannot enable the safety
  setting, keep violations on the existing `SqlErrorCode.constraint` path, and
  leave historical orphan detection or repair to explicit application work.
  Reject migrations that try to change the connection-owned setting.
- Define typed SQL projections with named `columns` and `decode` arguments,
  then decode through `SqlProjectionRow.read(selection)` so application
  records no longer depend on hand-maintained result indices.
  Resolve selections by exact identity, reject missing or repeated selections,
  and validate the complete row width before decoding. Keep positional
  `SqlRow` access only for the explicit raw-SQL transport path.
- Add the application-owned `odroe.yaml` with one explicit
  `sqlite_migrations` path. Full-stack starters now build and develop against
  their SQLite history without repeating a CLI flag, while
  `--sqlite-migrations` remains the one-command override. Keep projects without
  this config unselected and ignore it for Cloudflare-only builds so generic
  PostgreSQL or MySQL migration directories are never guessed.
- Build Native servers with `dart build cli` so dependency build and link hooks
  run in clean consumer projects. Publish the complete `bin/`, `lib/`, and
  optional `migrations/` bundle as one owned, rollback-safe directory, run
  prerender from its executable, preserve previous outputs on failure, and
  refuse to silently drop an already selected SQLite history. Preserve legacy
  standalone outputs for explicit operator cleanup instead of guessing how to
  migrate an adjacent history sidecar.
- Add an owned, lazy, bounded `MysqlDatabase.pool` without new dependencies or
  automatic retries. Bound physical connections, pending operations, and queue
  wait time independently; reject saturation as `SqlErrorCode.unavailable`.
  Keep transactions on one UTC connection, advance queued callers after failed
  opens, drain accepted work before close, preserve user errors, and retire any
  connection whose transaction state cannot be cleaned. Verify concurrency,
  backpressure, rollback, connection retirement, and shutdown against MariaDB
  11.8 while retaining the lower-cost serialized `open` path.
- Classify Cloudflare's documented D1 network, storage-reset, code-update-reset,
  and transient remote-node failures as `SqlErrorCode.unavailable` without
  exposing raw errors or retrying writes. Keep capacity, overload, resource, and
  large-write timeout failures classified as `driver` until a safer contract
  exists.
- Add type-safe atomic numeric updates through numeric
  `SqlTableColumn.incrementBy`, while keeping derived assignments out of
  INSERT APIs. Compile one bound `column = column + delta` statement across
  SQLite, PostgreSQL, MySQL/MariaDB, and D1, with negative deltas for decrement
  and explicit rejection of provider-dependent zero-delta no-ops.
- Replace the full-stack starter and reference app's unbounded post list with a
  typed ID-cursor page from SQL through generated RPC to Flutter
  `InfiniteQueryBuilder`. Enforce a 1–50 row request budget and use
  `limit + 1` to report the next cursor without an implicit count query.
- Add an append-only native SQLite migration runner with strict numbered SQL
  loading, exact applied-source verification, per-file atomic execution, and
  concurrent-startup locking. Let Native and Wrangler D1 consume the same
  application-owned history while keeping separate ledgers; explicitly select
  the SQLite source for Native bundles and prerender, watch it in development,
  and wire the contract through the full-stack starter and reference product.
  Validate route, migration, bundle, and prerender paths before any
  generated write, and serialize Native bundle publication across processes.
- Add provider-neutral `SqlQueries.countRows` for typed `COUNT(*)` over the
  existing table, join, and predicate path across SQLite, PostgreSQL,
  MySQL/MariaDB, and D1. Joined duplicates count as relation rows; ordering,
  pagination, grouping, and a general aggregate DSL remain outside the API.
- Add type-safe `SqlTableColumn.isIn` and `isNotIn` predicates across SQLite,
  PostgreSQL, MySQL/MariaDB, and D1. Non-null candidates are encoded eagerly;
  empty `isIn` and explicit Dart `null` candidates compile to portable predicates,
  while empty `isNotIn` is rejected before it can expose a full-table mutation.
- Add `odroe create <directory>` as the guarded source-stage product path from
  a nonexistent target through Flutter scaffold, Odroe dependency resolution,
  and the full-stack starter. Reject existing targets and remove only the
  private same-parent staging directory when any subprocess fails; publish the
  requested target only after the complete product succeeds.
- Make `odroe_flutter.dart` the selective Flutter composition root for
  `QueryModule`, `RpcModule`, `DocumentModule`, `RouterModule`, and `routerKey`.
  Generate one Odroe import in application `main.dart` while keeping route,
  server, and database source on narrow product entrypoints; atomically upgrade
  untouched starters that used the previous imports.
- Let adapter-neutral `server.dart` expose the platform-neutral application
  core its public server contracts already use. Generated server trees now need
  one Odroe server import instead of repeating `odroe.dart`.
- Add `odroe dev --server-target cloudflare --server-only` with a
  project-local Wrangler runtime, required initial route generation and
  source-to-Worker compilation, Dart source watching, atomic server JavaScript
  replacement, and last-known-good service when a subsequent generation or
  compilation fails.
- Bind each Query cache identity to an exact `QueryKey<T>` data type across
  options, reads, writes, infinite queries, hydration, and pending server
  handoff. Reject covariant or same-canonical type conflicts without replacing
  the existing cache entry.
- Add provider-neutral `SqlQueries.insertMany` for one typed multi-row INSERT,
  with complete shape validation before SQL construction and SQLite,
  PostgreSQL, MySQL/MariaDB, and Cloudflare D1 provider contracts.
- Generate symmetric typed RPC codecs for project-local named-record typedefs,
  including record inputs, outputs, collections, nullable values, and stream
  items. Upgrade the full-stack starter from a scalar read to typed post list
  and create flows across Flutter Query, ServerFunction, SQLite, and D1; the
  reference app additionally exercises typed post detail reads.
- Fail record RPC generation for ambiguous aliases, private or unsupported
  shapes, conditional or missing model imports, platform-specific shared
  libraries, and protocol-only values in collections or streams. Emit const
  generated function references backed by hot-reload-safe static codecs,
  deduplicate forwarded model imports, and avoid duplicate collection copies
  before serialization.
- Keep an active `MutationBuilder` execution and result attached when its
  options change; the new definition applies to the next execution. Reuse
  Query and Mutation options in the starter so unrelated widget rebuilds do
  not refetch stale lists or re-enable an in-flight create action.
- Add typed conflict-target `insertOnConflictDoNothing` for SQLite, Cloudflare
  D1, and PostgreSQL, with exact pre-I/O rejection on MySQL. Make the full-stack
  starter decode a complete `Post` record through the same typed projection
  used by its application writes.
- Add exact-cardinality `SqlRead.one` and `oneOrNull` terminals. Typed selects
  probe at most two rows while preserving offsets and explicit limits up to
  two; mutation `RETURNING` keeps its original statement and validates the
  returned rows.
- Persist the full-stack starter's native SQLite data at `.odroe/app.sqlite3`,
  allow `ODROE_SQLITE_PATH` and `ODROE_MIGRATIONS_PATH` overrides, and preserve
  existing rows through append-only migrations. Give prerender an isolated
  temporary database and remove it after the build.
- Return a controlled HTTP 400 for strict typed search decoding failures
  without invoking the route or server error reporter. Keep handler, loader,
  and codec encoding failures classified as unexpected server errors.
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
- Rebuild odroe.dev documentation as 17 product-first pages across start,
  tutorial, concepts, guides, and reference. Make the generated full-stack
  project the primary onboarding path, preserve old documentation URLs with
  redirects, and move website-only deployment operations out of public docs.
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
  drivers platform-isolated, track one shared SQLite/D1 SQL history, and export
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
