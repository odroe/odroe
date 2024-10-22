import 'package:flutter/material.dart';
import 'package:setup/setup.dart';

main() {
  runApp(const App());
}

class App extends SetupWidget {
  const App({super.key});

  @override
  Widget Function() setup() {
    final count = ref(0);
    provide(#count, count);

    return () => MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Count: ${count.value}')),
            floatingActionButton: const _Button(),
          ),
        );
  }
}

class _Button extends SetupWidget {
  const _Button();

  @override
  Widget Function() setup() {
    final count = inject<Ref<int>>(#count)!;

    return () => FloatingActionButton(
          onPressed: () => count.value++,
          child: Icon(Icons.add),
        );
  }
}
