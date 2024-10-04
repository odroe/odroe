import 'package:flutter/material.dart';
import 'package:oref/oref.dart';

main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final count = ref(0);

    final element = context as Element;
    element.visitChildren((child) {
      print(child);
    });

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Count: ${count.value}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            count.value++;
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
