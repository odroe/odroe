import 'package:flutter/widgets.dart';

abstract interface class Context<T> {
  String? get name;

  Widget provider({required T value, required Widget child}) {
    throw UnimplementedError();
  }

  T call() {
    throw UnimplementedError();
  }
}

Context createContext<T>([String? name]) {
  throw UnimplementedError();
}
