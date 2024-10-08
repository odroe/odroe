# Oncecall

Oncecall is a lightweight Flutter package that provides a simple and efficient way to memoize function calls within a build context. It helps optimize performance by ensuring that expensive computations are only performed once per build cycle.

## Features

- 🚀 Efficient Memoization: Caches function results to avoid redundant computations
- 🔄 Context-Aware: Automatically resets cache on rebuild
- 🎯 Easy to Use: Simple API that integrates seamlessly with Flutter widgets
- 🛠 Flexible: Works with any type of function and return value

## Getting started

Add `oncecall` to your `pubspec.yaml` file:

```yaml
dependencies:
  oncecall: ^0.0.1
```

Then, import the package in your Dart code:

```dart
import 'package:oncecall/oncecall.dart';
```

## Usage

Here's a simple example demonstrating how to use Oncecall:

```dart
import 'package:flutter/material.dart';
import 'package:oncecall/oncecall.dart';

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final expensiveResult = oncecall(context, () {
      // Expensive computation here
      return someExpensiveFunction();
    });

    return Text('Result: $expensiveResult');
  }
}
```

## Additional information

For more detailed information and advanced usage, please refer to the API documentation. If you encounter any issues or have suggestions, feel free to open an issue on the GitHub repository.
