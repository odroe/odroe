import 'package:_octr/_octr.dart';
import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

final _memorized = findOrCreateExpando<Scope>();

Scope getContextScope(BuildContext context) {
  final scope = _memorized[context];
  if (scope != null) return scope;

  final result = createScope(true);
  _memorized[context] = result;

  return result;
}
