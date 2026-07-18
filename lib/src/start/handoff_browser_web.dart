// ignore_for_file: deprecated_member_use, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:html';

Map<String, Object?>? readBrowserHandoff() {
  final element = document.querySelector('#__odroe_state__');
  final source = element?.text;
  element?.remove();
  if (source == null || source.isEmpty) return null;
  return Map<String, Object?>.from(jsonDecode(source) as Map);
}

Stream<Map<String, Object?>> browserHandoffFrames() {
  late final StreamController<Map<String, Object?>> controller;
  MutationObserver? observer;

  void consume(Element element) {
    if (element.attributes.containsKey('data-odroe-consumed')) return;
    element.attributes['data-odroe-consumed'] = '';
    final source = element.text;
    if (source == null || source.isEmpty) return;
    try {
      controller.add(Map<String, Object?>.from(jsonDecode(source) as Map));
    } on Object catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  void scan() {
    for (final element in document.querySelectorAll('[data-odroe-frame]')) {
      consume(element);
    }
  }

  controller = StreamController<Map<String, Object?>>(
    sync: true,
    onListen: () {
      scan();
      final root = document.body;
      if (root == null) return;
      observer = MutationObserver((_, _) => scan())
        ..observe(root, childList: true, subtree: true);
    },
    onCancel: () {
      observer?.disconnect();
      observer = null;
    },
  );
  return controller.stream;
}
