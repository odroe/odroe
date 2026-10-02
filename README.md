# Odroe

Odroe is a composable full-stack meta-framework for Dart and Flutter products.
It provides one application experience across typed file routes, Query and
Mutation, generated RPC, SQL, server delivery, and Flutter navigation.

The framework owns application conventions and the seams between these parts.
Independent packages can own matching, transport, runtime hosting, and other
reusable primitives. Roux is the current route-matching dependency; Spry and
oxy are not yet Odroe dependencies. Integrating them requires a tested contract,
not a package-name substitution.

## Source-stage status

This branch integrates the existing full-stack implementation as one product
chain. It is not a new hosted release. The old `odroe` 0.0.8 package on pub.dev
belongs to the previous UI API and must not be used for the examples below.
The current source package remains version 0.0.0 while release and migration
policy are decided. No 1.0 date is promised.

## SDK requirements

Use Flutter 3.38.1 or newer with stable Dart 3.10.0 or newer. The minimum
validated pair is Flutter 3.38.1 / Dart 3.10.0. Flutter 3.38.0 bundles a
prerelease Dart SDK that does not satisfy the stable Dart constraint; keep
Flutter's matching compiler and engine together.

[Minimum SDK CI](.github/workflows/minimum-sdk.yml) resolves the framework,
reference app and documentation without overrides, checks their contracts,
and runs a fresh generated RPC/SQLite application through a relocated native
server bundle. Platform-specific delivery still needs its own verification.

## Create a product

Use the source checkout with a complete Flutter package cache:

```sh
git clone https://github.com/odroe/odroe.git
cd odroe
flutter pub get
dart run odroe create ../my_app --odroe-path . --platforms web
cd ../my_app
dart run odroe generate
dart run odroe dev -- -d chrome
```

`create` builds Flutter's scaffold beside a nonexistent target, resolves the
selected Odroe checkout, initializes the full-stack starter, and publishes the
complete project. It preserves existing targets and rolls back incomplete
stages. Use `--offline` only when the package cache is complete. For an existing
empty Flutter product, use `dart run odroe init`; custom application source is
preserved and initialization refuses conflicts.

The starter connects Flutter Query/Mutation to generated typed RPC and a native
SQLite database. It includes bounded post pagination, creation, local record
and enum codecs, append-only SQL migrations, semantic document rendering,
prerendering, and native/Cloudflare server entrypoints. It also includes a locked
local Wrangler toolchain for the D1 preview path.

## Run and build

```sh
# Native server only; startup applies pending SQLite migrations.
dart run odroe dev --server-only

# Web product: Flutter assets, prerendered pages, and a native server bundle.
dart run odroe build web

# Native server bundle without Web assets.
dart run odroe build --server-only

# A native Flutter client must select its real API origin.
dart run odroe dev -- -d <device-id> \
  --dart-define=ODROE_RPC_ORIGIN=https://api.example.com
```

Web RPC defaults to the browser's origin. Native clients require an explicit
HTTP(S) server URI. The starter's `ODROE_RPC_ORIGIN` define accepts an origin
without credentials, a path, a query, or a fragment. `RpcModule.http` separately
accepts a valid HTTP(S) base URI and preserves existing endpoint resolution:
its default `/__odroe/functions` path starts at the server root. Invalid module
configuration fails before creating or using an HTTP client. Caller-owned
transports keep their ownership.

A native server build is a directory, normally `build/odroe/server`, containing
`bin/server` (`server.exe` on Windows), native libraries, configured migrations,
and, for a Web product, `build/web`. Deploy the complete bundle. The compiled
entrypoint validates its ownership marker and finds its root before creating
the application, so it can start from another working directory. Configure
`ODROE_SQLITE_PATH` to an absolute writable persistent volume in production;
the default `.odroe/app.sqlite3` is relative to the runtime root.

Odroe-managed build outputs must be strict relative descendants of `build/`.
Absolute paths, parent traversal, symbolic-link output components, and overlap
with source, generated routes, public assets, or migration history are rejected.
Document-only prerender output must be new or carry the matching project's
`.odroe-prerender` marker. Build stages preserve the previous published output
when compilation, rendering, or grouped publication fails. Cleanup failures
report retained paths without turning a successful publication into a failure.

## API boundaries

| Entrypoint | Responsibility |
| --- | --- |
| `odroe.dart`, `odroe_flutter.dart` | Application modules, context, lifetimes, Flutter composition |
| `router.dart`, `router_flutter.dart` | Typed routes, params/search, loaders, navigation |
| `query.dart`, `query_flutter.dart` | Typed cache identities, async reads, mutations, hydration |
| `rpc.dart` | Client references, HTTP transport, serialization, cancellation and budgets |
| `server.dart`, `server_io.dart` | Server functions, middleware, invocation, Dart IO hosting |
| `database.dart` | Provider-neutral typed SQL and result contracts |
| `database_sqlite.dart`, `database_postgres.dart`, `database_mysql.dart` | Native providers and owned connection lifetimes |
| `database_d1.dart`, `server_fetch.dart` | Preview D1 and Fetch runtime adapters |
| `document.dart`, `mdc.dart`, `press.dart`, `press_io.dart` | Semantic HTML, content parsing, page discovery |

Context keys are identity objects: construct one shared non-const `ContextKey<T>`
for each binding. Query keys now carry the exact cached data type as
`QueryKey<T>`; use `QueryKey<Object?>` only for prefix filters. Existing const
context-key declarations and cache keys shared across incompatible data types
need migration.

Server function definitions now import `server.dart`; client references remain
in `rpc.dart`. Generated client routes must not import the server tree, database
providers, or native code. SQL providers are opt-in Dart imports; their packages
are still resolved by the single package's pubspec. Import isolation does not
remove dependency-resolution cost.

SQLite migrations are explicit append-only history. Native startup validates
that history before serving requests, and changes to applied migrations stop
startup. PostgreSQL/MySQL transactions and pools own their documented lifecycle;
Odroe does not silently retry writes or perform remote migrations.

## Documentation and validation

- [Full-stack reference application](example/app)
- [First product](sites/odroe.dev/content/docs/getting-started.mdc)
- [Complete tutorial](sites/odroe.dev/content/docs/tutorials/full-stack.mdc)
- [Provider contracts](sites/odroe.dev/content/docs/guides/database-providers.mdc)
- [Deployment and artifact layout](sites/odroe.dev/content/docs/guides/deployment.mdc)
- [Support boundaries](sites/odroe.dev/content/docs/reference/support.mdc)

Public documentation is built by Odroe itself in `sites/odroe.dev`.
Local Workerd/D1 and Cloudflare build tests do not establish a deployed Worker.
Signed Android/iOS releases, real devices, remote databases, production TLS,
and Cloudflare account changes require separate validation. SQLite and native
bundle checks must run on the actual target architecture.

Release preparation still needs the existing project's license source, a
version/migration policy for users of the former UI package, a hosted-package
consumer. These are release
requirements, not reasons to replace the working source implementation.
