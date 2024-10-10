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
    final a = ref(context, 0);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Count: ${count.value}, A: ${a.value}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            if (count.value == a.value) {
              count.value++;
            } else {
              a.value++;
            }
          },
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}
