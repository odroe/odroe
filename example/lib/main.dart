import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Example',
      home: Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          Page(),
          Text('Counter: $count'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => count++),
        child: const Icon(Icons.plus_one),
      ),
    );
  }
}

class Page extends StatelessWidget {
  Page({super.key}) {
    print('Page c');
  }

  @override
  Widget build(BuildContext context) {
    print('page build');

    return TextButton(
      onPressed: () {
        Navigator.of(context).pop();
      },
      child: const Text('Back'),
    );
  }

  @override
  StatelessElement createElement() => PageElement(this);
}

class PageElement extends StatelessElement {
  PageElement(super.widget) {
    print('Page element 重建测试');
  }
}

void main(List<String> args) {
  runApp(App());
}
