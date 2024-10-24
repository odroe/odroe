import 'package:flutter/material.dart';
import 'package:setup/setup.dart';

main() {
  runApp(const App());
}

class App extends SetupWidget {
  const App({super.key});

  @override
  Widget Function() setup() {
    final testWidget = useWidgetRef<TestWidget>(#test);
    void handleRebuildTest() {
      testWidget.widget?.handleRebuild();
    }

    onUpdated(() {
      print('App updated');
    });

    return () {
      return MaterialApp(
        home: Scaffold(
          body: Center(child: TestWidget(ref: #test)),
          floatingActionButton: FloatingActionButton(
            onPressed: handleRebuildTest,
            child: Text('Rebuild'),
          ),
        ),
      );
    };
  }
}

class TestWidget extends SetupWidget {
  TestWidget({super.key, super.ref});
  late final _version = ref(1);

  @override
  Widget Function() setup() {
    onUpdated(() {
      print('Test updated');
    });

    return () => Text('TestWidget rebuild: ${_version.value}');
  }

  void handleRebuild() => _version.value++;
}
