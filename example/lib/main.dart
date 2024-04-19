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

      print('demo' + counter.get().toString());

      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: Text('Counter: ${counter.get()}'),
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

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
