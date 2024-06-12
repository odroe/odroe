import 'package:flutter/material.dart';
import 'package:odroe/src/box.dart';
import 'package:odroe/src/style_sheet.dart';

void main() {
  runApp(const MaterialApp(
    title: "Playground",
    home: Home(),
  ));
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(children: [
      Box(
        style: StyleSheet(width: 100, height: 64),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.red),
        ),
      ),
    ]);
  }
}
