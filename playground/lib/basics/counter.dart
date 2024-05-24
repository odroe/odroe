import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
      final count = signal(0);
      void increment() => count.value++;

      return () => Scaffold(
            appBar: AppBar(title: const Text('Counter')),
            body: Center(child: Text('Count: ${count.value}')),
            floatingActionButton: FloatingActionButton(
              onPressed: increment,
              child: const Icon(Icons.plus_one),
            ),
          );
    });
