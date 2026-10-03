# Preview releases

Keep `pubspec.yaml`, `lib/src/cli/version.dart`, the changelog, and installation
and migration documentation on the same release version. A candidate's version
does not need to exist on pub.dev for pull-request or main CI to pass.

## Before publication

Merge the release preparation through normal CI, then use a clean checkout of
the resulting main commit and the selected Flutter SDK:

```sh
python3 test/support/release_preflight.py --output .odroe/release-preflight
```

Choose a new empty output directory for each attempt. This runs pub's dry run,
then its separate local-only `--to-archive` operation. The generated archive
respects pub's inclusion rules and `.pubignore`; `git archive` is not a
substitute. Do not skip validation. The hidden archive option must work on the
selected SDK; an unsupported option is a failed gate, not permission to upload.
CI runs this in a separate clean checkout: SDK compatibility checks may resolve
different versions in the documentation application's lockfile, which is not
part of the published package.

The script rejects links, traversal paths, duplicate members, and special files
before using the extracted package. Its consumers run the extracted package's
CLI and path dependency while obtaining fixtures from the checkout. Generated
RPC/SQLite and a relocated native server, direct dependency adoption, and
incremental Query/routing/HTTP RPC, and the ordinary read bridge must all pass.
The read bridge consumer uses the extracted public entrypoint on native HTTP
and real Chrome, including document-base URL resolution. Route identity uses
the extracted dependency for native navigation, then a temporary copy with only
the browser external-navigation adapter instrumented for Chrome. Its fixtures
come from the checkout. Research files and test fixtures must not enter the
archive.

Keep the archive and `manifest.json` together. The manifest records the exact
source commit, version, SDK, archive SHA256, and every shipped file's checksum.
Only a complete manifest with passed archive consumers represents a successful
preflight. These results do not establish official hosted availability.

Publish that same validated archive after reviewing the frozen identity:

```sh
flutter pub publish --from-archive=.odroe/release-preflight/odroe-0.1.0-dev.3.tar.gz
```

Pub's archive input does not rerun the original source validation, which is why
the preceding dry run and exact archive consumption are required. Never modify
or substitute the archive after validation. If an upload result is uncertain,
query the exact official version and checksum before considering another upload.
Published versions cannot be replaced.

## After publication

Run the `Published release acceptance` workflow manually with the exact version,
full main commit SHA, and preflight archive SHA256. It has read-only permissions
and does not publish. The same acceptance can run locally:

```sh
python3 test/support/release_verify.py \
  --version 0.1.0-dev.3 --commit FULL_MAIN_COMMIT \
  --archive-sha256 PREFLIGHT_ARCHIVE_SHA256 --output .odroe/published-release
```

The official index and downloaded archive must match the frozen identity. Every
shipped file must also match pub's archive of the exact source commit. The
downloaded official package supplies both the interpreted and compiled CLI;
each default create resolves the same exact version in a fresh official cache.
Direct and incremental consumers also use fresh hosted dependencies without
overrides. A checkout launcher targeting an older package is not acceptance of
the newly published CLI.

If the registry has not propagated yet, repeat read-only checks for a bounded
period. Do not silently select a different version or substitute local files.
A reproducible product defect after publication requires a subsequent version,
not a rewritten artifact or tag.
