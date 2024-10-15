---
title: Documentation → Oref → Introduction
description: A low-invasive reactive system for Dart/Flutter.
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → A low-invasive reactive system for Dart/Flutter.
prev: false
---

{{ $frontmatter.description }}

In many frameworks, similar reactive base types are called "signals". Fundamentally, Oref has the same reactive base type as the signal concept.
It is a value container that tracks dependencies when accessed and triggers side effects when changed.

## What is reactivity?

Essentially, reactivity is a programming paradigm that allows us to handle changes declaratively. Many front-end frameworks emphasize its importance:

- [Preact.js Signals](https://preactjs.com/blog/introducing-signals/)
- [Vue.js In-Depth Reactivity](https://vuejs.org/guide/extras/reactivity-in-depth.html#what-is-reactivity)
- [Solid Signals](https://www.solidjs.com/docs/latest/api#createsignal)
- [Dart: `signals` package](https://dartsignals.dev/reference/overview)

## Installation

You can directly add Oref to any Dart project using this command:

```bash
dart pub add oref
```

Or modify your `pubspec.yaml` file:

```yaml
dependencies:
  oref: latest
```

## Basic Usage

```dart
import 'package:oref/oref.dart';

void main() {
  final count = ref(0);
  final double = derived(() => count.value * 2);
  final runner = effect(() {
    print('count: ${count.value}, double: ${double.value}');
  }, onStop: () {
    print('effect stopped');
  });

  count.value = 10; // Prints 'count: 10, double: 20'

  // Stop the effect
  runner.effect.stop(); // Prints 'effect stopped'

  count.value = 20; // No effect

  // If the effect is stopped, we can run it manually once.
  runner(); // Prints 'count: 20, double: 40'

  count.value = 30; // No effect
}
```
