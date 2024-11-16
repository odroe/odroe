import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends OdroeWidget {
  const ExampleApp({super.key});

  @override
  WidgetRender setup() {
    final count = ref(0);

    effect(() {
      print(count.value);
    });

    return h(
      () => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Count: ${count.value}')),
          floatingActionButton: FloatingActionButton(
            onPressed: () => count.value++,
            child: const Icon(Icons.plus_one),
          ),
        ),
      ),
    );
  }
}
