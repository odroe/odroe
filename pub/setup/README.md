Setup is a Dart framework for building user interfaces. It is built on top of Flutter and provides a
declarative, reactive programming model. It helps you develop Flutter applications efficiently.

- **Reactivity**: Uses the [`oref`](https://odroe.dev/packages/oref) reactivity system for efficient UI rebuilding.
- **Performance**: Code in `setup()` is executed only once, with automatic dependency collection and release without manual handling.
- **Composition API**: Better logic reuse, more flexible code organization; easily compose reusable logic.
- **User-friendly API**: Intuitive, designed with developer experience in mind.

## Installation

Add `setup` to your `pubspec.yaml`:

```yaml
dependencies:
  setup: latest
```

Then run:

```
flutter pub get
```

## Sponsorship

If you find Setup helpful, please consider [sponsoring the project](https://github.com/sponsors/medz). Your support helps maintain and improve the framework.

<p align="center">
  <a target="_blank" href="https://github.com/sponsors/medz#:~:text=Featured-,sponsors,-Current%20sponsors">
    <img alt="sponsors" src="https://github.com/medz/public/raw/main/sponsors.tiers.svg">
  </a>
</p>

## Quick Start

Here's a simple example of how to use Setup:

```dart
import 'package:flutter/material.dart';
import 'package:setup/setup.dart';

void main() {
  runApp(const CounterApp());
}

class CounterApp extends SetupWidget {
  const CounterApp();

  @override
  Widget Function() setup() {
    final count = ref(0);
    void increment() => count.value++;

    return () {
      return MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Count: ${count.value}')),
          floatingActionButton: FloatingActionButton(
            onPressed: increment,
            child: Icon(Icons.plus_one),
          ),
        ),
      );
    };
  }
}
```

## Documentation

> [!WARNING]
> WIP

For more detailed information and advanced usage, please refer to our [official documentation](https://odroe.dev/setup).

## License

Setup is released under the MIT License.
