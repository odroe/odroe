import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
      final counter = useConunter();

      return Scaffold(
        appBar: AppBar(title: demo(counter.value.toString())),
        // appBar: AppBar(title: const Text('Counter')),
        body: Center(
          child: Text('Count: ${counter.value}, Double: ${counter.double}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: counter.increment,
          child: const Icon(Icons.plus_one),
        ),
      );
    });

Widget demo(String value) => setup(props: value, () {
      return Text('Counter: $value');
    });

typedef Result = ({int value, int double, VoidCallback increment});

Result useConunter() {
  final count = $state(0);
  final double = $computed(() => count.get() * 2, [count]);

  return (
    value: count.get(),
    double: double.get(),
    increment: () => count.update((value) => value + 1),
  );
}
