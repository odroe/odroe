import 'package:flutter/material.dart';

// ignore: implementation_imports
import 'package:odroe/src/core/framework.dart';
// ignore: implementation_imports
import 'package:odroe/src/core/api_reactivity.dart';
// ignore: implementation_imports
import 'package:odroe/src/core/api_context.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends OdroeWidget {
  const ExampleApp({super.key});

  @override
  Widget build() {
    final count = ref(0);
    final context = useContext();

    print(count.hashCode);

    // print(MediaQuery.sizeOf(context));

    return MaterialApp(
      home: const Scaffold(
        body: Center(child: Text('Home')),
      ),
    );
  }
}
