---
title: Documentation → Memoization (Oncecall)
description: Oncecall is a memoization tool for the Flutter Widget build method. It allows your code to be called only once in the build method, even if the Widget is rebuilt.
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Memoization (Oncecall)
prev: false
next: false
---

{{ $frontmatter.description }}

## Why do we need it?

We always want to construct use cases that have dynamic properties and conform to `const` Widgets, or we have some logic that must be placed in the `build` method.

Oncecall allows you to write code in `build` that runs only once.

## Installation

We use the following command:

```bash
flutter pub add oncecall
```

Or add in `pubspec.yaml`:

```yaml
dependencies:
  oncecall: latest
```

## Basic Usage

```dart
class MyWidget extends StatelessWidget {
    const MyWidget({super.key});

    Widget build(BuildContext context) {
        oncecall(context, () => print('Will only run once'));

        return ...;
    }
}
```

This doesn't seem to be any different. But without oncecall, you would write the following code:

```dart
class MyWidget extends StatelessWidget {
    MyWidget({super.key}) {
        print('Will only run once'); // Widget rebuild might execute again
    }

    Widget build(BuildContext context) {
        return ...;
    }
}
```

## For One-time Calculations

The `oncecall()` function, in addition to being used for one-time functions, can also perform some object initialization work:

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    Widget build(BuildContext context) {
        final value = oncecall(context, () {
            ...
        });

        return ...;
    }
}
```

## More

As a foundational part of the Odroe ecosystem, you'll see Oncecall everywhere in other packages. It is a very low-level and simple API, and as its name suggests, it is only used for value memoization and initialization work that depends on context.
