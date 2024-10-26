import 'package:flutter/material.dart';
import 'package:setup/setup.dart';

main() {
  runApp(const App());
}

class App extends SetupWidget {
  const App({super.key});

  @override
  Widget Function() setup() {
    final testWidgetRef = useWidgetRef<TestWidget>();
    final count = ref(0);

    increment() async {
      count.value++; // Update count value, current count value is 1

      // Widget has not been updated
      // print(testWidgetRef.value?.count); // 0

      await nextTick();
      // Widget has been updated at this time
      // print(testWidgetRef.value?.count); // 1
    }

    return () {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: obs(count, (value) => TestWidget(value, ref: testWidgetRef)),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: increment,
            child: Text('+1'),
          ),
        ),
      );
    };
  }
}

class TestWidget extends SetupWidget {
  const TestWidget(this.count, {super.key, super.ref});

  final int count;

  @override
  Widget Function() setup() {
    final ref = useWidgetRef<TestWidget>();

    onUpdated(() {
      print('Updated');
    });

    effect(() => print(ref.value?.count));

    return () {
      return Text('Count: ${ref.value?.count}');
    };
  }
}
