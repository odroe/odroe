import 'package:example/theme.dart';
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'counter.dart';

typedef Example = ({
  String route,
  String title,
  Widget Function() component,
});

final examples = <Example>[
  (route: '/counter', title: 'Counter', component: counter),
];

Widget exampleBuilder(BuildContext context, int index) {
  final example = examples[index];

  return Card(
    child: Text(example.title),
  );
}

Widget home() => setup(() {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Odroe Examples'),
          actions: [
            themeModeIconButton(),
          ],
        ),
        body: ListView.builder(
          itemCount: examples.length,
          itemBuilder: exampleBuilder,
        ),
      );
    });

Widget themeModeIconButton() => setup(() {
      final mode = $store(modeThemeStore);

      void switchMode() {
        final newMode = mode == ThemeMode.light
            ? ThemeMode.dark
            : mode == ThemeMode.system
                ? ThemeMode.light
                : mode == ThemeMode.dark
                    ? ThemeMode.system
                    : ThemeMode.light;
        modeThemeStore.set(newMode);
      }

      return IconButton(
        onPressed: switchMode,
        icon: Icon(switch (mode) {
          ThemeMode.system => Icons.auto_awesome,
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
        }),
      );
    });
