import 'package:flutter/material.dart';

T state<T>(T initialValue) => initialValue;

extension<T> on T {
  void update(T Function(T) up) {}
}

Widget counter() => FC(() {
      final count = state(0);

      return Text('Counter: $count');
    });

WidgetBuilder demo() {
  final count = state(1);

  void add() => count.update((value) => value++);

  return FC(() {});

  return (ctx) {
    return Column(
      children: [
        Text('Count: $count'),
        TextButton(
          onPressed: add,
          child: const Text('Plus'),
        ),
      ],
    );
  };
}

void main(List<String> args) {
  Column(
    children: [
      ~demo(),
    ],
  );
}

extension on WidgetBuilder {
  operator ~() {
    // TODO: Create FC wrapper widget to be binding hooks
    return this;
  }
}
