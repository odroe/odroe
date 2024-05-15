import 'package:flutter/material.dart';

import 'pages/alert.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Odroe/UI Playground',
      home: AlertDefaultPage(),
    );
  }
}

main() => runApp(const App());
