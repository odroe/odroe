# odroe.dev

The official website is an Odroe Document + Press application. Public product
documentation lives in `content/docs`; this file owns repository-specific
build and deployment operations that should not appear in user documentation.

## Local quality gate

Run from this directory:

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test
npm ci
npm run build
npm run deploy:check
```

`npm run build` executes the assets-only `dart run odroe build --no-server`
path. `deploy:check` runs the locked Wrangler 4.146.0 dry-run against
`wrangler.jsonc` and `build/web`; it does not authenticate or upload.

Preview Cloudflare's static-asset routing locally:

```sh
npm run preview
```

Check `/`, `/docs`, `/site.css`, `/robots.txt`, and `/sitemap.xml`. `/docs/`
must canonicalize to `/docs`; an unknown route must return the generated 404.

## Remote deployment authorization

A remote deploy creates or replaces the `odroe-dev` Worker version and changes
traffic. It requires explicit authorization naming the target Cloudflare
account. A custom domain, DNS record, or certificate is a separate state change
and requires separate authorization.

Before approval, `npm run deploy:status` is read-only. Do not treat an auth,
network, or provider error as proof that no deployment exists.

After approval:

1. Confirm `npm run deploy:account` matches the authorized account ID.
2. Require a clean worktree.
3. Record the full reviewed Git SHA.
4. Re-run `npm run build` and `npm run deploy:check`.
5. Require the worktree to remain clean after the build.
6. Deploy with the Git SHA in the version message.
7. Read deployments and versions back from Cloudflare.
8. Confirm the expected version receives 100% of traffic.
9. Smoke the exact URL printed by Wrangler; never guess an account subdomain.

The application gate is:

```sh
(
  set -eu
  export CLOUDFLARE_ACCOUNT_ID='authorized-account-id'
  npm run deploy:account -- --account "$CLOUDFLARE_ACCOUNT_ID"
  test -z "$(git status --porcelain)"
  export ODROE_DEPLOY_SHA="$(git rev-parse HEAD)"
  npm run build
  npm run deploy:check
  test -z "$(git status --porcelain)"
  npm run deploy -- --message "git:$ODROE_DEPLOY_SHA"
  npm run deploy:status
  npm run deploy:versions
)
```

Stop before smoke testing when the account, version, message, or traffic
readback differs from the authorization. Do not modify `build/web` between the
final dry-run and deployment.

The minimum remote smoke covers `/`, `/docs`, one concept page, one guide,
`/site.css`, `/robots.txt`, `/sitemap.xml`, the `/docs/` canonical redirect,
one legacy documentation redirect, and an unknown route returning 404.
