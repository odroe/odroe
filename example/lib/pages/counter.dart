import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
      final counter = $state(0);

      void increment() => counter.set(counter.get() + 1);

      return Scaffold(
        appBar: AppBar(title: const Text('Counter')),
        // body: Center(
        //   child: Text('Count: ${counter.get()}'),
        // ),
        body: show(counter.get().toString()),
        floatingActionButton: FloatingActionButton(
          onPressed: increment,
          child: const Icon(Icons.plus_one),
        ),
      );
    });

Widget show(String value) => setup(props: value, () {
      final demo = $state(0);

      return TextButton(
        onPressed: () => demo.update((value) => value + 1),
        child: Text('Super: $value, Local: ${demo.get()}'),
      );

      // print(demo);

      // return Text(value);
    });
