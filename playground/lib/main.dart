import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget countText(int count) {
  defineProps([count]);

  return setup(() {
    final [count] = props();
    return () => Center(child: Text('Count: $count'));
  });
}

Widget counter() => setup(() {
      final count = signal(0);
      void onPressed() => count.value++;

      return () => Scaffold(
            appBar: AppBar(title: const Text('Counter')),
            body: countText(count.value),
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
