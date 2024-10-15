---
title: Documentation → Oref → Quick Start
description: Installation and basic usage guide for Oref in Dart/Flutter
head:
  - - meta
    - property: og:title
      content: Odroe | Installation and basic usage guide for Oref in Dart/Flutter
---

{{ $frontmatter.description }}

## Installation

Oref provides two packages:

| Name | Version | Description |
|----|----|----|
| `oref` | [![Pub Version](https://img.shields.io/pub/v/oref)](https://pub.dev/packages/oref) | Reactive core |
| oref_flutter | [![Pub Version](https://img.shields.io/pub/v/oref_flutter)](https://pub.dev/packages/oref_flutter) | Integration of Oref with Flutter |

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

## Declaring Reactive State

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

## Declaring Reactive Collections

::: tip WIP
In development, please read our [roadmap](https://github.com/odroe/odroe/issues/17).
:::
