import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

/// Reads and removes the embedded initial handoff payload.
Map<String, Object?>? readBrowserHandoff() {
  final element = document.querySelector('#__odroe_state__');
  final source = element?.textContent;
  element?.remove();
  if (source == null || source.isEmpty) return null;
  return Map<String, Object?>.from(jsonDecode(source) as Map);
}

/// Streams handoff frames appended by the server.
Stream<Map<String, Object?>> browserHandoffFrames() {
  late final StreamController<Map<String, Object?>> controller;
  MutationObserver? observer;

  void consume(Element element) {
    if (element.hasAttribute('data-odroe-consumed')) return;
    element.setAttribute('data-odroe-consumed', '');
    final source = element.textContent;
    if (source == null || source.isEmpty) return;
    try {
      controller.add(Map<String, Object?>.from(jsonDecode(source) as Map));
    } on Object catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  void scan() {
    final elements = document.querySelectorAll('[data-odroe-frame]');
    for (var index = 0; index < elements.length; index++) {
      final element = elements.item(index);
      if (element != null) consume(element as Element);
    }
  }

  controller = StreamController<Map<String, Object?>>(
    sync: true,
    onListen: () {
      scan();
      final root = document.body;
      if (root == null) return;
      observer = MutationObserver(
        ((JSArray<MutationRecord> _, MutationObserver _) => scan()).toJS,
      )..observe(root, MutationObserverInit(childList: true, subtree: true));
    },
    onCancel: () {
      observer?.disconnect();
      observer = null;
    },
  );
  return controller.stream;
}

/// Hides the semantic HTML after Flutter paints its first frame.
void hideBrowserDocument() {
  document.querySelector('#__odroe_document__')?.setAttribute('hidden', '');
}
