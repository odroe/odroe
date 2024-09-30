import 'package:flutter/widgets.dart';

import 'types.dart';

ComputedRef<T> computed<T>(BuildContext context, T Function() getter) {
  return _ComputedRef(getter);
}

class _ComputedRef<T> extends ComputedRef<T> {
  _ComputedRef(this.compute);

  final T Function() compute;
  T? innerValue;

  @override
  // TODO: implement value
  T get value => throw UnimplementedError();
}
