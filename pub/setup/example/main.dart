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
