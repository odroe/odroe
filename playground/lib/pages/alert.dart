import 'package:flutter/material.dart' hide Colors;
import 'package:odroe/ui.dart';

class AlertDefaultPage extends StatelessWidget {
  const AlertDefaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: const [
          Alert(),
          Button(text: Text('Hello')),
        ],
      ),
    );
  }
}
