## v0.4.1

- Correct pub metadata information

## v0.4.0

2024-10-21

## What's New

- **feat**: Support [`untracked`](https://odroe.dev/docs/oref/advanced#untracked) api
- **feat**: Support [`batch`](https://odroe.dev/docs/oref/advanced#batch) api
- **feat**: Support [`customRef`](https://odroe.dev/docs/oref/advanced#custom-ref) api
- **feat**: Support [`reactiveMap`](https://odroe.dev/docs/oref/core#reactive-collections) api
- **feat**: Support [`reactiveSet`](https://odroe.dev/docs/oref/core#reactive-collections) api
- **feat**: Support [`reactiveList`](https://odroe.dev/docs/oref/core#reactive-collections) api
- **feat**: Support [`reactiveIterable`](https://odroe.dev/docs/oref/core#reactive-collections) api
- **feat**: Support [`isReactive`](https://odroe.dev/docs/oref/utils#is-reactive) api
- **feat**: Support [`toRaw`](https://odroe.dev/docs/oref/advanced#to-raw) api
- **feat**: [PRIVATE] - Base ref class support `raw` prop, sub impl cleanup internal to raw.

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
