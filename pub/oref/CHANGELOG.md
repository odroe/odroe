## v0.3.0

2024-10-10

## What's New

- **feat**: Exports the `on`/`off` API for `Scope`.

## v0.2.0

2024-10-09

## What's New

- **feat**: Adds `watch` function.

## v0.1.0

To install Oref v0.1.0, run this command:

```bash
dart pub add oref:^0.1.0
```

Otherwise, to upgrade your `pubspec.yaml` file:

```yaml
dependencies:
  oref: ^0.1.0
```

### What's Changed

- **feat**: Adds `stop`/`pause`/`resume` methods to `Effect` interface.
- **BREAKING CHANGE**: The `effect` function now returns a `EffectRunner`.
- **BREAKING CHANGE**: Remove the `writableDerived`, now you can use `derived.writable`.
- **BREAKING CHANGE**: Remove the `derivedWith`, now you can use `derived.valuable`.
