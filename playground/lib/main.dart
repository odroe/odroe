import 'package:flutter/material.dart';
import 'package:setup/setup.dart';

main() {
  runApp(const App());
}

class App extends SetupWidget {
  const App({super.key});

  @override
  Widget Function() setup() {
    final viewSize = ref<Size?>(null);
    final context = useContext();

    // ⚠️ You cannot directly use context in setup
    // because the Widget has not been mounted yet.
    // viewSize.value = MediaQuery.maybeSizeOf(context);

    onMounted(() {
      // Can safely use context
      viewSize.value = MediaQuery.maybeSizeOf(context);
    });

    return () {
      // Context can be safely used in render
      print(MediaQuery.maybeSizeOf(context));

      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Observer(() => Text('View Size: ${viewSize.value}')),
          ),
        ),
      );
    };
  }
}
