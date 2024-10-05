import 'package:flutter/material.dart';
import 'package:oref_flutter/oref_flutter.dart';

main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final demo = ref(0);
    final b = ref(0);

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Count: ${demo.value}, ${b.value}'),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            demo.value++;
            if (demo.value % 2 == 0) {
              b.value++;
            }
          },
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}
