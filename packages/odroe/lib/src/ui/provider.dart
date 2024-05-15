import 'package:flutter/widgets.dart';

class Provider<T> extends StatelessWidget {
  const Provider({super.key, required this.data, required this.child});

  final T data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Inherited(provider: this, child: child);
  }

  static T? of<T>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_Inherited<T>>()
        ?.provider
        .data;
  }
}

class _Inherited<T> extends InheritedWidget {
  const _Inherited({required super.child, required this.provider});

  final Provider<T> provider;

  @override
  bool updateShouldNotify(covariant _Inherited<T> oldInherited) {
    return oldInherited.provider.data != provider.data;
  }
}
