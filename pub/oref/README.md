# Oref

Oref is a lightweight, high-performance reactive programming library for Dart.
It provides a concise yet powerful way to manage application state and side effects.

## Features

- 🚀 High Performance: Optimized reactive system ensures fast state updates with minimal overhead
- 🧩 Modularity: Easy to integrate into existing projects without enforcing a specific application architecture
- 🔍 Fine-grained Reactivity: Precisely tracks and updates dependencies, avoiding unnecessary computations
- 🛠 Flexible API: Supports various reactive programming patterns, including refs, derived properties, and effects
- ✨ **100%** Native: Zero dependencies, pure Dart implementation

## Installation

Run the following command to install Oref:
```bash
dart pub add oref
```

Or add the following line to your `pubspec.yaml` file:

```yaml
dependencies:
  oref: latest
```

## Quick Start

Here's a simple example demonstrating how to use Oref:

```dart
import 'package:oref/oref.dart';

void main() {
  final count = ref(0);
  final doubleCount = derived(() => count.value * 2);

  effect(() {
    print('Count: ${count.value}, Double: ${doubleCount.value}');
  });

  count.value++; // Will trigger the effect and print new values
}
```
