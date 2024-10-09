import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart';

Scope getContextScope(BuildContext context) {
  return oncecall(context, () => createScope(true));
}
