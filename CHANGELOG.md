# Changelog

## Unreleased

- Add typed SQL, typed inner and left joins, and SQLite, PostgreSQL,
  MySQL/MariaDB, and Cloudflare D1 entrypoints.
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
