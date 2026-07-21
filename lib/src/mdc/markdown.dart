import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;

import 'ast.dart';

/// Internal Markdown sentinel used for component invocations.
const mdcComponentTag = 'x-odroe-mdc-component';

/// Internal Markdown sentinel used for named slots.
const mdcSlotTag = 'x-odroe-mdc-slot';

/// Internal Markdown sentinel used for element attributes.
const mdcAttributeTag = 'x-odroe-mdc-attributes';

/// Internal sentinel attribute containing a component or slot name.
const mdcNameAttribute = 'data-mdc-name';

/// Internal sentinel attribute containing encoded typed properties.
const mdcPropertiesAttribute = 'data-mdc-properties';

/// Converts package:markdown nodes into the immutable MDC AST.
List<MdcNode> convertMarkdownNodes(List<markdown.Node> nodes) {
  final result = <MdcNode>[];
  for (final node in nodes) {
    if (node is markdown.Element && node.tag == 'p') {
      final converted = _convertElement(node);
      if (converted.children.isEmpty &&
          converted.attributes.isNotEmpty &&
          result.isNotEmpty) {
        final previous = result.last;
        if (previous is MdcElement) {
          result[result.length - 1] = _withAttributes(
            previous,
            converted.attributes,
          );
          continue;
        }
      }
      result.add(converted);
      continue;
    }
    result.add(_convertNode(node));
  }
  return List<MdcNode>.unmodifiable(result);
}

MdcNode _convertNode(markdown.Node node) => switch (node) {
  markdown.Text node => MdcText(node.text),
  markdown.Element node when node.tag == mdcComponentTag => _convertComponent(
    node,
  ),
  markdown.Element node => _convertElement(node),
  _ => throw StateError('Unsupported Markdown node ${node.runtimeType}.'),
};

MdcComponent _convertComponent(markdown.Element element) {
  final children = <MdcNode>[];
  final slots = <String, MdcSlot>{};
  for (final child in element.children ?? const <markdown.Node>[]) {
    if (child is markdown.Element && child.tag == mdcSlotTag) {
      final name = child.attributes[mdcNameAttribute]!;
      slots[name] = MdcSlot(
        properties: _decodeProperties(child),
        children: convertMarkdownNodes(
          child.children ?? const <markdown.Node>[],
        ),
      );
    } else {
      children.add(_convertNode(child));
    }
  }
  return MdcComponent(
    element.attributes[mdcNameAttribute]!,
    properties: _decodeProperties(element),
    children: children,
    slots: slots,
  );
}

MdcElement _convertElement(markdown.Element element) {
  final attributes = <String, String?>{
    for (final entry in element.attributes.entries)
      if (entry.key != mdcPropertiesAttribute) entry.key: entry.value,
  };
  final children = <MdcNode>[];
  for (final child in element.children ?? const <markdown.Node>[]) {
    if (child is markdown.Element && child.tag == mdcAttributeTag) {
      final converted = _elementAttributes(_decodeProperties(child));
      if (children.isNotEmpty) {
        final previous = children.last;
        if (previous is MdcElement) {
          children[children.length - 1] = _withAttributes(previous, converted);
          continue;
        }
      }
      _mergeElementAttributes(attributes, converted);
      continue;
    }
    children.add(_convertNode(child));
  }
  if (element.attributes[mdcPropertiesAttribute] != null) {
    _mergeElementAttributes(
      attributes,
      _elementAttributes(_decodeProperties(element)),
    );
  }
  return MdcElement(element.tag, attributes: attributes, children: children);
}

MdcElement _withAttributes(
  MdcElement element,
  Map<String, String?> attributes,
) {
  final merged = <String, String?>{...element.attributes};
  _mergeElementAttributes(merged, attributes);
  return MdcElement(
    element.tag,
    attributes: merged,
    children: element.children,
  );
}

void _mergeElementAttributes(
  Map<String, String?> target,
  Map<String, String?> additions,
) {
  for (final entry in additions.entries) {
    if (entry.key == 'class') {
      final current = target['class'];
      if (current != null) {
        target['class'] = '$current ${entry.value}';
        continue;
      }
    }
    target[entry.key] = entry.value;
  }
}

Map<String, String?> _elementAttributes(Map<String, Object?> properties) =>
    <String, String?>{
      for (final entry in properties.entries)
        if (entry.value == true)
          entry.key: null
        else if (entry.value != false && entry.value != null)
          entry.key: switch (entry.value) {
            String value => value,
            num value => value.toString(),
            _ => throw FormatException(
              'Element attribute "${entry.key}" must be a scalar.',
            ),
          },
    };

Map<String, Object?> _decodeProperties(markdown.Element element) {
  final source = element.attributes[mdcPropertiesAttribute];
  if (source == null) return const <String, Object?>{};
  return jsonDecode(source) as Map<String, Object?>;
}
