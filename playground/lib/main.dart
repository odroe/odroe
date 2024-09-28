import 'package:flutter/material.dart';
import 'package:oref/oref.dart';

main() {
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  String name = 'Seven';

  @override
  Widget build(BuildContext context) {
    provide(context, #name, name);

    return MaterialApp(
      home: Scaffold(
        body: const Center(
          child: Demo(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              name = DateTime.now().toString();
            });
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) {
    print('Demo build');

    return const Center(
      child: Name(),
    );
  }
}

class Name extends StatelessWidget {
  const Name({super.key});

  @override
  Widget build(BuildContext context) {
    final name = inject(context, #name);

    return Center(
      child: Text('Hello, $name'),
    );
  }
}
