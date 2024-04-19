import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget app() => setup(() {
      final theme = state(ThemeData());

      return MaterialApp(
        theme: theme.get(),
        title: 'Example',
        home: home(),
      );
    });

Widget home() => setup(() {
      final counter = state(0);
      final demo = computed(() => counter.get() % 2, [counter]);

      effect(() {
        print('demo: ${demo.get()}, counter: ${counter.get()}');

        return () => print('Clean up');
      });

      effect(() {
        print('AAA');

        return () => print('AAA: clean up');
      }, [counter]);

      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: Text('Counter: ${counter.get()}, ${demo.get()}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => counter.set(counter.get() + 1),
          child: plusIcon(),
        ),
      );
    });

Widget plusIcon() => setup(() {
      return const Icon(Icons.plus_one);
    });

void main(List<String> args) {
  runApp(app());
}
