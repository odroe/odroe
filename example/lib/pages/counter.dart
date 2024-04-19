import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
      final counter = $state(0);

      void increment() => counter.set(counter.get() + 1);

      return Scaffold(
        appBar: AppBar(title: const Text('Counter')),
        body: Center(
          child: Text('count: ${counter.get()}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: increment,
          child: const Icon(Icons.plus_one),
        ),
      );
    });
