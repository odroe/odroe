import 'package:example/theme.dart';
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget home() => setup(() {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Odroe Examples'),
          actions: [
            themeModeIconButton(),
          ],
        ),
        body: ListView(
          children: [],
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
