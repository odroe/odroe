```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
    final count = signal(0);

    void increment() => count.value++;

    return () => TextButton(
        onPressed: increment,
        child: Text('Count: ${count.value}'),
    );
});
```
