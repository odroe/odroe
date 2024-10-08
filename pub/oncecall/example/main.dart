import 'package:flutter/material.dart';
import 'package:oncecall/oncecall.dart';

void main() {
  runApp(const App());
}

int counter = 0;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final value = oncecall(context, () => ++counter);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          // It is always "Count: 1" because it is memoized.
          child: Text('Count: $value'),
        ),
      ),
    );
  }
}
