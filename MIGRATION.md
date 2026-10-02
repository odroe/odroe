# Migrating to the Odroe 0.1 framework

Odroe 0.1.0-dev.1 is the first preview of a new full-stack framework generation
under the existing package name. It is a breaking change from the former UI
package. Existing published 0.0.8 versions remain available; no 1.0 release
date is promised.

## Existing UI applications

Keep the existing resolved UI dependency while planning migration. An exact `odroe: 0.0.8` constraint makes that choice explicit; normal `^0.0.8` does not select a 0.1 framework version. Replacing the old dependency with the framework source does not preserve its APIs.

The old `setup`, `signal`, reactive props, lifecycle hooks and UI context APIs are not compatibility exports of the framework. The verified `setup`/`signal` counter fails to analyze against the framework because those symbols are missing. For that small counter, a standard Flutter `StatefulWidget` can hold an integer and update it using `setState`. More involved signal graphs and lifecycle code need their own migration; this counter is not a general automatic conversion.

## New framework applications

For source evaluation, use Flutter 3.38.1 / stable Dart 3.10.0 or a newer validated pair. For hosted installation, add the exact `odroe` version `0.1.0-dev.2` to an existing or empty Flutter application and import the APIs you need, as shown in the README. `init` and `create` are optional starter tools; direct use does not require initialization or generated files.

Framework App/Module/Context, Query/Mutation, typed routes, generated RPC and SQL are separate contracts from the former UI API. Roux is the actual matching dependency; Spry and oxy are not integrated.

## 0.1.0-dev.2: Query client ownership

`QueryClientProvider(child: app)` now creates and owns one QueryClient. Its
optional `create:` callback runs once per owned lifetime; ordinary rebuilds and
callback changes retain the cache. Use a new widget key to reset the lifetime.

Change existing `QueryClientProvider(client: client, child: app)` calls to
`QueryClientProvider.value(client: client, child: app)` to preserve borrowing.
Borrowed clients are never cleared by the provider. Use
`QueryClientProvider.of(context)` to read the live client; the old widget
`client` field is removed. QueryModule and QueryBuilder usage is unchanged.

This API is not present in the published `0.1.0-dev.1` package. See the
[incremental adoption guide](sites/odroe.dev/content/docs/guides/incremental-adoption.mdc)
for complete Query, manual-routing, and RPC consumption.

## Earlier framework source

- Import server function definitions from `server.dart`; client references remain in `rpc.dart`. Regenerate routes and keep generated client imports free of server/database/native code.
- Create one shared non-const `ContextKey<T>` per binding. These keys compare by identity; recreating one at each lookup changes the binding.
- Use the exact cached data type in `QueryKey<T>`. Reserve `QueryKey<Object?>` for prefix filters.
- Deploy the complete native bundle with its ownership marker, native libraries and migration files. Copying only `bin/server` is insufficient. Use a persistent absolute `ODROE_SQLITE_PATH` and retain applied migration history.
- Keep `ODROE_RPC_ORIGIN` for native client API selection. Configure validated `ODROE_PUBLIC_ORIGIN` when a fixed public server origin is required, following the documented factory and proxy trust contracts.
- Importing a single entrypoint does not avoid resolving the current single pubspec's provider dependencies/native hooks.

Validated Mac/Linux SQLite/native and local Workerd/D1 checks do not establish signed mobile/device, Windows, remote database or remote Cloudflare deployment support. These are outside the closing task.
