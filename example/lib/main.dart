import 'package:flutter/material.dart';
import 'package:odroe/framework.dart';

void main() {
  runApp(o | app());
}

WidgetBuilder app() {
  return (context) {
    return MaterialApp(
      title: 'Odroe App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: o | home(),
    );
  };
}

WidgetBuilder home() {
  return (context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Odroe App'),
      ),
      body: const Center(
        child: Text('Hello, Odroe!'),
      ),
    );
  };
}
