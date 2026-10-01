# Odroe full-stack reference app

A Flutter product using explicit modules, typed file routes, Query/Mutation,
generated record and enum RPC codecs, typed SQL, semantic HTML, and prerendering.
The post list uses bounded keyset pagination; post creation refreshes the list
from server state. Query cancellation propagates to the underlying RPC request.

```sh
flutter pub get
dart run odroe generate
dart run odroe dev -- -d chrome
dart run odroe dev --server-only
dart run odroe build web
```

Native Flutter clients must pass
`--dart-define=ODROE_RPC_ORIGIN=https://api.example.com` with their real server
origin. Web keeps same-origin RPC. The define must contain an HTTP(S) origin
without credentials, path, query, or fragment.

## Database and runtime

Shared route handlers import `database.dart`. Native startup opens a
process-owned SQLite file, applies the configured append-only migrations, and
closes it with the server. The default `.odroe/app.sqlite3` persists across
restarts. Use `ODROE_SQLITE_PATH` and `ODROE_MIGRATIONS_PATH` for explicit runtime
paths. Production data should live on an absolute writable persistent volume.
Editing, removing, or renaming applied migration files stops startup.

The native build is a complete owned directory with its executable, native
libraries, migrations, and optional Web output. Deploy the whole directory.
The compiled server locates the bundle root independently of the launch working
directory and rejects a missing, damaged, or symbolic-link ownership marker.
`build --server-only` deliberately excludes Web assets.

The Fetch entrypoint uses D1 through the same provider-neutral handlers. To try
that preview locally, install the locked Node toolchain, initialize local D1,
and keep every Wrangler command local:

```sh
flutter pub get
dart run odroe generate
npm ci
dart run odroe build --no-server web
npm run cloudflare:migrate:local
npm run cloudflare:dev
```

A successful local Workerd test or bundle build does not establish a remote
Cloudflare deployment or mobile release. See the repository's
[full-stack tutorial](../../sites/odroe.dev/content/docs/tutorials/full-stack.mdc)
and [deployment guide](../../sites/odroe.dev/content/docs/guides/deployment.mdc).

The locked Node toolchain declares `engines` and `devEngines`; install the
required versions before running the local preview.
