import 'package:flutter/material.dart';
import 'package:oref_flutter/oref_flutter.dart';

main() {
  runApp(const App());
}

int counter = 0;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final count = ref(context, 0);

    void handle() {
      count.value++;
    }

    effect(context, () {
      print(count.value);
    });

    print(22222);

    return MaterialApp(
      home: Scaffold(
        body: const Center(
          child: Text('Count:'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: handle,
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}
