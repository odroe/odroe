import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart';

import '../global.dart';
import '../setup_widget.dart';

/// A reference to a [SetupWidget] and its associated [BuildContext].
///
/// The [WidgetRef] provides access to a [SetupWidget] of type [T] and its
/// [BuildContext]. The widget reference is read-only.
abstract final class WidgetRef<T extends SetupWidget> implements Ref<T?> {
  /// The [BuildContext] associated with the referenced widget, if available.
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

/// Creates a reference to a [SetupWidget] of type [T].
///
/// This function creates a [WidgetRef] that provides access to the closest
/// ancestor widget of type [T] in the widget tree. If no such widget exists,
/// the reference will contain null.
///
/// The reference is automatically registered with the current element if the
/// element's widget matches type [T].
///
/// Returns a [WidgetRef<T>] that can be used to access the referenced widget
/// and its build context.
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
