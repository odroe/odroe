# Odroe

Odroe is a composable full-stack meta-framework for Dart and Flutter products.
It provides one application experience across typed file routes, Query and
Mutation, generated RPC, SQL, server delivery, and Flutter navigation.

The framework owns application conventions and the seams between these parts.
Independent packages can own matching, transport, runtime hosting, and other
reusable primitives. Roux is the current route-matching dependency; Spry and
oxy are not yet Odroe dependencies. Integrating them requires a tested contract,
not a package-name substitution.

## Framework preview

Version 0.1.0-dev.1 starts a new full-stack framework generation. The old
`odroe` 0.0.8 package on pub.dev provides a different UI API; its `setup`, `signal`, props and
lifecycle helpers are not compatibility exports here. Read the
[migration guide](MIGRATION.md) before upgrading. Existing `^0.0.8` dependencies
do not select this 0.1 preview. No 1.0 date is promised.

## SDK requirements

Use Flutter 3.38.1 or newer with stable Dart 3.10.0 or newer. The minimum
validated pair is Flutter 3.38.1 / Dart 3.10.0. Flutter 3.38.0 bundles a
prerelease Dart SDK that does not satisfy the stable Dart constraint; keep
Flutter's matching compiler and engine together.

[Minimum SDK CI](.github/workflows/minimum-sdk.yml) resolves the framework,
reference app and documentation without overrides, checks their contracts,
and runs a fresh generated RPC/SQLite application through a relocated native
server bundle. Platform-specific delivery still needs its own verification.

This checkout targets `0.1.0-dev.3`. Hosted installation requires that exact
version to be available on pub.dev; publication is verified separately.

## Add Odroe to your Flutter app

Use an existing Flutter application, or start with an empty one:

```sh
flutter create --empty --platforms web my_app
cd my_app
flutter pub add 'odroe:{"version":"0.1.0-dev.3"}'
```

Replace `lib/main.dart` with this application:

```dart
import 'package:flutter/widgets.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';

final greeting = QueryOptions<String>(
  key: QueryKey<String>('welcome'),
  policy: const QueryPolicy(
    freshness: QueryFreshness.staleAfter(Duration(minutes: 5)),
  ),
  query: (_) async => 'Hello from Odroe',
);

final home = AppRoute<NoParams, NoSearch, NoData>(path: '/').page(
  build: (_) => Center(
    child: QueryBuilder<String>(
      options: greeting,
      builder: (_, result) =>
          Text(result.hasData ? result.requireData : 'Loading'),
    ),
  ),
);

final about = AppRoute<NoParams, NoSearch, NoData>(
  path: '/about',
).page(build: (_) => const Center(child: Text('About this app')));

Widget createApp() => App(
  modules: [
    QueryModule(),
    RouterModule(routes: [home, about]),
  ],
  builder: (app) => WidgetsApp.router(
    color: const Color(0xff222222),
    routerConfig: app.read(routerKey),
  ),
);

void main() => runApp(createApp());
```

Run and build it with the standard Flutter commands:

```sh
flutter run -d chrome
flutter build web --release
```

Adding the dependency and importing the APIs is enough. This application uses
App, Query, and manually declared routes without `odroe init`, generated files,
or an `odroe.yaml` configuration. Select only the modules your application
needs; Query and routing can also be used through their individual entrypoints.

Query owns the asynchronous greeting and its cache. RouterModule accepts the
two route objects directly. A server, database, or RPC origin is only needed
when your application uses those capabilities.

For an existing Flutter application, follow the
[incremental adoption guide](sites/odroe.dev/content/docs/guides/incremental-adoption.mdc).
It separates a Query-only provider from optional routing and HTTP RPC, including
explicit owned and borrowed provider lifetimes in `0.1.0-dev.2`.

## Optional full-stack starter

To explore the generated Query/RPC/SQLite starter alongside the application
above, create a separate empty Flutter project:

```sh
cd ..
flutter create --empty --platforms web full_stack_app
cd full_stack_app
flutter pub add 'odroe:{"version":"0.1.0-dev.3"}'
dart run odroe init --full-stack
dart run odroe dev -- -d chrome
```

`init` is an optional template tool. It preserves custom application source and
refuses conflicts rather than replacing it. Plain `dart run odroe init` writes
a smaller Document + Router starter.

Starting with `0.1.0-dev.2`, the CLI can also create the entire application.
From an application or checkout with that dependency resolved:

```sh
dart run odroe create ../my_app --platforms web
```

By default, `create` pins the hosted dependency to the exact version of the CLI
running the command. It does not select `latest`. Override the version with
`--version 0.1.0-dev.1`, or use `--odroe-path .` for a checkout dependency; the
two overrides cannot be combined. The hosted package's installed CLI supplies
its initializer and generated routes. If that exact version is unavailable,
creation fails without publishing an incomplete application.

Hosted creation requires the `0.1.0-dev.2` CLI or newer. The older
`0.1.0-dev.1` CLI supports the add-dependency and optional `init` paths.
For source development:

```sh
git clone https://github.com/odroe/odroe.git
cd odroe
flutter pub get
dart run odroe create ../my_app --odroe-path .
cd ../my_app
```

`create` requires a nonexistent target and stages the Flutter application beside
it before publication. Failed or interrupted stages remove only that private
directory and preserve existing targets. Use `--platforms`, `--org`, or
`--project-name` to customize the scaffold. `--offline` requires the selected
package and all its dependencies in the local cache.

File-based routing and automatic RPC codecs use generated Dart source. For
those features, `odroe generate` runs the compiler explicitly; `odroe dev` and
`odroe build` run it as part of their workflow. Ordinary Flutter commands do
not generate file-route manifests. Handwritten routes need no generation.

The full-stack starter connects Flutter Query/Mutation to generated typed RPC
and SQLite, with pagination, local record and enum codecs, migrations, document
rendering, and native/Cloudflare server entrypoints. Follow the
[first application guide](sites/odroe.dev/content/docs/getting-started.mdc) for
the starter layout and its optional server workflows.

## Run and build the full-stack starter

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
| `query_rpc.dart` | Since `0.1.0-dev.3`. Ordinary typed RPC reads and exact/collection Query filters |
| `server.dart`, `server_io.dart` | Server functions, middleware, invocation, Dart IO hosting |
| `database.dart` | Provider-neutral typed SQL and result contracts |
| `database_sqlite.dart`, `database_postgres.dart`, `database_mysql.dart` | Native providers and owned connection lifetimes |
| `database_d1.dart`, `server_fetch.dart` | Preview D1 and Fetch runtime adapters |
| `document.dart`, `mdc.dart`, `press.dart`, `press_io.dart` | Semantic HTML, content parsing, page discovery |

**Since `0.1.0-dev.3`:**
`query_rpc.dart` adds `ref.read(rpc, input, scope: ['tenant', 'account'])`,
`ref.readAt(...)` and `ref.reads(...)` to existing value refs. Calling `read`
explicitly declares the function idempotent and safe for retries and refetches.
It returns native `QueryOptions<O>`;
filters use the same endpoint, scope and encoded input identity. Own each
`RpcClient` per account/backend, and let its headers provider read only that
account's refreshable credentials. Tokens and ambient cookies are not cache
identity. Web relative URLs follow the document base; native reads require an
explicit HTTP(S) server URI. Raw responses and streams use direct RPC instead.
Pagination and mutation invalidation remain explicit native Query definitions.
Client cancellation excludes late results; server notification is transport
best-effort and may never arrive.

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
- [First application](sites/odroe.dev/content/docs/getting-started.mdc)
- [Complete tutorial](sites/odroe.dev/content/docs/tutorials/full-stack.mdc)
- [Provider contracts](sites/odroe.dev/content/docs/guides/database-providers.mdc)
- [Deployment and artifact layout](sites/odroe.dev/content/docs/guides/deployment.mdc)
- [Support boundaries](sites/odroe.dev/content/docs/reference/support.mdc)

Public documentation is built by Odroe itself in `sites/odroe.dev`.
Local Workerd/D1 and Cloudflare build tests do not establish a deployed Worker.
Signed Android/iOS releases, real devices, remote databases, production TLS,
and Cloudflare account changes require separate validation. SQLite and native
bundle checks must run on the actual target architecture.

Odroe is licensed under the [MIT license](LICENSE), retaining the project's
original Odroe Inc. copyright notice. This preview's
[version/migration policy](MIGRATION.md) separates the new framework from the
former UI package. A hosted-package consumer must install the exact preview
without source paths or dependency overrides; source/archive checks alone do
not establish hosted-package installation.
