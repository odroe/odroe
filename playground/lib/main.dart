import 'package:flutter/material.dart';
import 'package:oncecall/oncecall.dart';

main() {
  runApp(const App());
}

int counter = 0;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final test = oncecall(context, () {
      print(11111);
      return counter++;
    });
    final demo = oncecall(context, () => counter++);
    final c = oncecall(context, () => counter++);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Count: $test, $demo, $c'),
        ),
      ),
    );
  }
}
