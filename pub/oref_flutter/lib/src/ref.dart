import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

oref.Ref<T> ref<T>(BuildContext context, T value) {
  return oncecall(context, () => oref.ref(value));
}
