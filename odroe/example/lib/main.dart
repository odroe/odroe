import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends OdroeWidget {
  const ExampleApp({super.key});

  @override
  Widget build() {
    return MaterialApp(
      home: const Counter(),
    );
  }
}
