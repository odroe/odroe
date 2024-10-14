import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oref_flutter/oref_flutter.dart';

main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final count = ref(context, 0);
    final timer = Timer.periodic(Duration(seconds: 1), (_) {});

    timer.cancel;

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Count: ${count.value}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => count.value++,
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}
