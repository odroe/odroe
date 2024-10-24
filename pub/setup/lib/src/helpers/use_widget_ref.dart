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

abstract interface class WidgetRef<T extends SetupWidget>
    implements Ref<SetupElement?> {
  BuildContext? get context;
  T? get widget;
}

final class WidgetRefImpl<T extends SetupWidget>
    implements oref_private.Ref<SetupElement?>, WidgetRef<T> {
  WidgetRefImpl(this.key, [this.raw]);

  final Symbol key;

  @override
  late final oref_private.Dep dep = oref_impl.Dep();

  @override
  SetupElementImpl? raw;

  @override
  SetupElementImpl? get value {
    dep.track();
    return raw;
  }

  @override
  @internal
  @Deprecated('Widget ref unsupported calling setter')
  set value(_) {
    if (kDebugMode) {
      debugPrint('odroe/setup: Widget ref do not allow calling setter');
    }
  }

  @override
  BuildContext? get context => value;

  @override
  T? get widget => value?.widget as T?;
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
      currentElement,
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

void setWidgetRef(SetupElement parent, Symbol key, dynamic element) {
  final ref = _widgetRefs[parent]?.where((ref) => ref.key == key).singleOrNull;
  if (ref != null && ref.raw == null) {
    ref.raw = element;
  }
}

void triggerWidgetRef(SetupElement parent, Symbol key) {
  final ref = _widgetRefs[parent]?.where((ref) => ref.key == key).singleOrNull;
  if (ref != null) {
    ref.dep.trigger();
  }
}
