import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart' as oref;

oref.Derived<T> derived<T>(BuildContext context, T Function() compute) {
  throw UnimplementedError();
}

oref.Scope createScope(BuildContext context, [bool detached = false]) {
  throw UnimplementedError();
}

oref.EffectRunner<T> effect<T>(
  BuildContext context,
  T Function() runner, {
  void Function()? scheduler,
  void Function()? onStop,
}) {
  throw UnimplementedError();
}

oref.WatchHandle watch<T>(
  BuildContext context,
  T Function() compute,
  void Function(T value, T? oldValue) runner, {
  bool immediate = false,
  bool once = false,
}) {
  throw UnimplementedError();
}
