import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

final examples = [
  (path: '/counter', title: 'Counter'),
  (path: '/timer', title: 'Timer'),
];

Widget home() => setup(() {
      return Scaffold(
        appBar: AppBar(title: const Text('Odroe Examples')),
        body: ListView.builder(
          itemBuilder: _itemBuilder,
          itemCount: examples.length,
        ),
      );
    });

Widget _itemBuilder(BuildContext context, int index) {
  assert(index < examples.length);

  final (:title, :path) = examples[index];
  final navigator = Navigator.of(context);

  return ListTile(
    title: Text(title),
    onTap: () => navigator.pushNamed(path),
  );
}
