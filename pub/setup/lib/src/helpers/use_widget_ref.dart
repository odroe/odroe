import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

import '../global.dart';
import '../setup_widget.dart';

abstract final class WidgetRef<T extends SetupWidget> implements Ref<T?> {
  BuildContext? get context;
}

final class WidgetReferenceImpl<T extends SetupWidget> implements WidgetRef<T> {
  const WidgetReferenceImpl(this.elementRef);

  final Ref<SetupElementImpl?> elementRef;

  @override
  T? get value => elementRef.value?.widget as T?;

  @override
  set value(_) {
    if (kDebugMode) {
      debugPrint('WidgetRef is readonly.');
    }
  }

  @override
  BuildContext? get context => elementRef.value;
}

WidgetRef<T> useWidgetRef<T extends SetupWidget>() {
  final elementRef = switch (currentElement) {
    SetupElementImpl element when element.widget is T => ref(element),
    _ => ref<SetupElementImpl?>(null),
  };

  final widgetRef = WidgetReferenceImpl<T>(elementRef);
  if (currentElement != null && currentElement?.widget is T) {
    currentElement!.widgetRefs.add(widgetRef);
  }

  return widgetRef;
}
