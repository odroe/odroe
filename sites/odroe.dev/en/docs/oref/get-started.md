---
title: Documentation → Oref → Quick Start
description: Installation and basic usage guide for Oref in Dart/Flutter
head:
  - - meta
    - property: og:title
      content: Odroe | Installation and basic usage guide for Oref in Dart/Flutter
---

{{ $frontmatter.description }}

## Installation {#installation}

Oref provides two packages:

| Name | Version | Description |
|----|----|----|
| `oref` | [![Pub Version](https://img.shields.io/pub/v/oref)](https://pub.dev/packages/oref) | Reactive core |
| `oref_flutter` | [![Pub Version](https://img.shields.io/pub/v/oref_flutter)](https://pub.dev/packages/oref_flutter) | Integration of Oref with Flutter |

We use the following commands for installation:

::: code-group

```bash [Dart Project]
dart pub add oref
```
```bash [Flutter]
flutter pub add oref_flutter
```
:::

Or update your `pubspec.yaml` file:

::: code-group
```yaml [Dart Project]
dependencies:
  oref: latest
```
```yaml [Flutter]
dependencies:
  oref_flutter: latest
```
:::

## Declaring Reactive State {#declaring-reactive-state}

To declare a reactive state, we use the `ref()` function

::: code-group
```dart [Dart]
final count = ref(0)
```
```dart [Flutter]
final count = ref(context, 0)
```
:::

`ref()` accepts parameters and returns a `Ref<T>` object wrapped with a `.value` property:

::: code-group
```dart [Dart]
void main() {
    final count = ref(0);

    print(count); // Ref<int>
    print(count.value); // 0

    count.value++;
    print(count.value); // 1
}
```
```dart [Flutter]
class MyWidget extends StatelessWidget {
    const MyWidget({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0); // [!code focus]

        return TextButton(
            onPressed: () => count.value++, // [!code focus]
            child: Text('Count: ${count.value}'), // [!code focus]
        );
    }
}
```
:::

## Declaring Reactive Collections {#declaring-reactive-collections}

::: tip WIP
In development, please read our [roadmap](https://github.com/odroe/odroe/issues/17).
:::

## Fine-grained Rebuilding <Badge type="tip" text="Flutter" /> {#fine-grained-rebuild}

For example, in the Counter code from the [Declaring Reactive State](#declaring-reactive-state) example, when we update the value of `count`, the entire `Counter` Widget gets rebuilt.
This is unnecessary, as we only need to rebuild the `Text`.

It is recommended to use the `Observer` Widget for optimization:

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: Observer( // [!code focus]
                builder: (_) => Text('Count: ${count.value}'), // [!code focus]
            ), // [!code focus]
        );
    }
}
```

When the internal value of `count` updates, only the `Text` will be rebuilt.
However, `Observer` is suitable for collecting multiple reactive values. For simple usage, we recommend the `obs()` function:

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: count.obs((value) => Text('Count: ${value}')), // [!code focus]
        );
    }
}
```

> [!TIP]
> For more details about `obs()`, please check [Core → Observable](/docs/oref/core#obs).

There are multiple ways to implement fine-grained rebuild:

* Use `Observer` to wrap and observe reactive data.
* Use [`obs()`](/docs/oref/core#obs) for observation.
* Use [`derived() - Derivation`](/docs/oref/core#derived) to combine values.
