import 'package:flutter/material.dart';
import 'package:odroe/next.dart';

Widget counter() => setup(() {
      final count = signal(0);
      void onPressed() => count.value++;

      return () => Scaffold(
            appBar: AppBar(title: const Text('Counter')),
            body: Text('Count: ${count.value}'),
            floatingActionButton: FloatingActionButton(
              onPressed: onPressed,
              child: const Icon(Icons.plus_one),
            ),
          );
    });

Widget app() => setup(() => () => MaterialApp(
      title: 'Odreo Playground',
      home: counter(),
    ));

main() => runApp(app());
