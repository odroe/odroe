import 'package:flutter/material.dart';
import 'package:oinject/oinject.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    provide(context, 'Provide from App widget');

    return MaterialApp(home: _Home());
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: _ShowProvidedText()),
    );
  }
}

class _ShowProvidedText extends StatelessWidget {
  const _ShowProvidedText();

  @override
  Widget build(BuildContext context) {
    final text = inject<String>(context);

    return Text(text!);
  }
}
