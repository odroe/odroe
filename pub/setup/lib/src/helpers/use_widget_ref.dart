import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';
import 'package:meta/meta.dart';

// ignore: implementation_imports
import 'package:oref/src/impls/dep.dart' as oref_impl;
// ignore: implementation_imports
import 'package:oref/src/types/private.dart' as oref_private;

import '../global.dart';
import '../setup_widget.dart';

abstract interface class WidgetRef<T extends SetupWidget> implements Ref<T?> {
  @override
  @internal
  @Deprecated('Widget ref unsupported calling setter')
  set value(T? _);
}

final class WidgetRefImpl<T extends SetupWidget>
    implements oref_private.Ref<T?>, WidgetRef<T> {
  WidgetRefImpl(this.key, [this.raw]);

  final Symbol key;

  @override
  T? raw;

  @override
  late final oref_private.Dep dep = oref_impl.Dep();

  @override
  T? get value {
    dep.track();
    return raw;
  }

  @override
  set value(T? _) {
    if (kDebugMode) {
      debugPrint('odroe/setup: Widget ref do not allow calling setter');
    }
  }
}

class SetupElementSymbol implements Symbol {
  const SetupElementSymbol(this.element);

  final SetupElement element;

  @override
  int get hashCode => Object.hash(runtimeType, element);

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType && hashCode == other.hashCode;
  }
}

final _widgetRefs =
    Expando<List<WidgetRefImpl>>('odroe/setup: widget cached refs');

WidgetRef<T> useWidgetRef<T extends SetupWidget>([Symbol? key]) {
  assert(currentElement != null,
      'odroe/setup: Cannot be called outside of SetupWidget');
  assert(T != SetupWidget || key != null,
      'odroe/setup: Please provide a specific SetupWidget subclass or a non-null key');

  if (currentElement == null) {
    throw FlutterError(
        'odroe/setup: Call useWidgetRef() outside of Setup Widget');
  } else if (T == SetupWidget && key == null) {
    throw FlutterError(
        'odroe/setup: Please provide a specific SetupWidget subclass or a non-null key');
  } else if (key == null && currentElement!.widget is T) {
    final ref = WidgetRefImpl<T>(
      SetupElementSymbol(currentElement!),
      currentElement!.widget as T,
    );

    (_widgetRefs[currentElement!] ??= []).add(ref);
    return ref;
  } else if (key == null) {
    if (kDebugMode) {
      debugPrint(
          'odroe/setup: Please provide a specific SetupWidget subclass or a non-null key');
    }
    return WidgetRefImpl<T>(#odroe.setup.void_widget_ref);
  }

  final exists =
      _widgetRefs[currentElement!]?.where((ref) => ref.key == key).singleOrNull;
  if (exists is WidgetRef<T>) {
    return exists as WidgetRef<T>;
  }

  final ref = WidgetRefImpl<T>(key);
  (_widgetRefs[currentElement!] ??= []).add(ref);
  return ref;
}

setWidgetRef(SetupElement parent, Symbol key, SetupWidget value,
    {bool trigger = true}) {
  final ref = _widgetRefs[parent]?.where((ref) => ref.key == key).singleOrNull;

  ref?.raw = value;
  if (trigger &&
      ref != null &&
      ref.raw != value &&
      Widget.canUpdate(ref.raw!, value)) {
    ref.dep.trigger();
  }
}
