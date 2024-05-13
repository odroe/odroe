import 'package:flutter/material.dart';
import 'package:odroe/next.dart';

final app = setup.z(() {
  Widget app() {
    return MaterialApp(
      title: 'Odroe Playgound',
      home: reversal(home.zero),
    );
  }

  return () => fire(app);
});

final home = setup.z(() {
  Widget text() => const Text('Hello Odore');

  return () => fire(text);
});

main() {
  final widget = reversal(app.zero);

  return runApp(widget);
}
