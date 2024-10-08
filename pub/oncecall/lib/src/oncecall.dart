import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';

final _evalCtxRef = findOrCreateEval<BuildContext>();
final _evalCount = findOrCreateExpando<int>();
final _memoirzed = findOrCreateExpando<Map<int, dynamic>>();

T oncecall<T>(BuildContext context, T Function() fn) {
  // Internal, share context.
  _evalCtxRef.value = context;

  WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) {
    _evalCount[context] = null;
  });

  final count = _evalCount[context] ??= 0;
  final memoirzed = _memoirzed[context] ??= <int, dynamic>{};
  final value = memoirzed[count];

  _evalCount[context] = count + 1;
  if (value is T && memoirzed.containsKey(count)) {
    return value;
  }

  return memoirzed[count] = fn();
}
