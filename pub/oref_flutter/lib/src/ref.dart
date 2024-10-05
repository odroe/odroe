import 'package:flutter/widgets.dart';
import 'package:oref/oref.dart' as oref;

import 'utils/find_element.dart';

final _cachedElements = Expando<List<Element>>();
final _evalCount = Expando<int>();
final _cachedRefs = Expando<Map<int, List<oref.Ref>>>();
final _pendingRefs = Expando<List<oref.Ref>>();

extension WidgetRefWidget on Widget {
  oref.Ref<T> ref<T>(T value) {
    final elements = _cachedElements[this] ??= [];
    var evalCount = _evalCount[this] ??= 0;

    Element? element;
    if (evalCount < elements.length) {
      element = elements[evalCount];
      if (!Widget.canUpdate(element.widget, this)) {
        // Cleanup if the widget has changed
        elements.removeAt(evalCount);
        element = null;
      }
    }

    if (element != null) {
      final refs = _cachedRefs[element] ??= {};
      final refList = refs[evalCount] ??= [];

      if (refList.isNotEmpty) {
        final ref = refList.removeAt(0);
        if (ref is oref.Ref<T>) {
          _evalCount[this] = evalCount + 1;
          return ref;
        }
      }
    }

    // Create new ref if not found in cache
    final ref = oref.ref(value);

    // Add ref to pending list
    final pendingRefs = _pendingRefs[this] ??= [];
    pendingRefs.add(ref);

    // Schedule findElement and cleanup for next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final newElement = findElement(this);
        elements.add(newElement);

        final refs = _cachedRefs[newElement] ??= {};
        final refList = refs[evalCount] ??= [];
        refList.addAll(pendingRefs);
      } catch (e) {
        // Use a logging framework instead of print
        print('Error finding element: $e');
        // Reset counts if element not found
        _evalCount[this] = 0;
        _cachedElements[this]?.clear();
        // Optionally, you might want to reset the findElement count as well
        resetFindElementCount(this);
      }

      pendingRefs.clear();
    });

    _evalCount[this] = evalCount + 1;

    return ref;
  }
}

// Add this function to reset the count in findElement
void resetFindElementCount(Widget widget) {
  findElement(widget); // This will reset the count internally
}
