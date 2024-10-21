import 'package:flutter/widgets.dart';
import 'package:oncecall/oncecall.dart';
import 'package:oref/oref.dart' as oref;

import 'internal/widget_effect.dart';

/// Creates a reactive map that can be used in a widget context.
///
/// This function takes a [BuildContext] and a [Map] as input, and returns
/// a reactive version of the map that can be used within a widget.
/// The returned map will trigger rebuilds when its contents change.
Map<K, V> reactiveMap<K, V>(BuildContext context, Map<K, V> map) {
  ensureInitializedWidgetEffect(context);
  return oncecall(context, () => oref.reactiveMap(map));
}

/// Creates a reactive set that can be used in a widget context.
///
/// This function takes a [BuildContext] and a [Set] as input, and returns
/// a reactive version of the set that can be used within a widget.
/// The returned set will trigger rebuilds when its contents change.
Set<E> reactiveSet<E>(BuildContext context, Set<E> set) {
  ensureInitializedWidgetEffect(context);
  return oncecall(context, () => oref.reactiveSet(set));
}

/// Creates a reactive list that can be used in a widget context.
///
/// This function takes a [BuildContext] and a [List] as input, and returns
/// a reactive version of the list that can be used within a widget.
/// The returned list will trigger rebuilds when its contents change.
List<E> reactiveList<E>(BuildContext context, List<E> list) {
  ensureInitializedWidgetEffect(context);
  return oncecall(context, () => oref.reactiveList(list));
}

/// Creates a reactive iterable that can be used in a widget context.
///
/// This function takes a [BuildContext] and an [Iterable] as input, and returns
/// a reactive version of the iterable that can be used within a widget.
/// The returned iterable will trigger rebuilds when its contents change.
Iterable<E> reactiveIterable<E>(BuildContext context, Iterable<E> iterable) {
  ensureInitializedWidgetEffect(context);
  return oncecall(context, () => oref.reactiveIterable(iterable));
}
