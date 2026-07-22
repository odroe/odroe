import 'ast.dart';

/// One heading in an MDC document outline.
final class MdcOutlineEntry {
  /// Creates an immutable outline entry.
  MdcOutlineEntry({
    required this.id,
    required this.title,
    required this.level,
    Iterable<MdcOutlineEntry> children = const <MdcOutlineEntry>[],
  }) : children = List<MdcOutlineEntry>.unmodifiable(children);

  /// The heading fragment identifier without a leading `#`.
  final String id;

  /// The plain inline text of the heading.
  final String title;

  /// The HTML heading level from 1 through 6.
  final int level;

  /// More deeply nested headings in document order.
  final List<MdcOutlineEntry> children;
}

/// Heading utilities for an immutable [MdcDocument].
extension MdcDocumentOutline on MdcDocument {
  /// Returns this document with a stable `id` on every heading.
  ///
  /// Existing IDs are preserved. Generated IDs are derived from plain heading
  /// text, preserve non-Latin text, and avoid every explicit or previously
  /// generated ID in the document. Unchanged nodes are reused.
  MdcDocument withHeadingIds() => _indexHeadings(this).document;

  /// Returns the document headings as an immutable hierarchy.
  ///
  /// Heading IDs use the same rules as [withHeadingIds], even when this
  /// document has not yet been transformed. A heading becomes a child of the
  /// nearest preceding heading with a lower level.
  List<MdcOutlineEntry> get outline => _indexHeadings(this).outline;
}

({MdcDocument document, List<MdcOutlineEntry> outline}) _indexHeadings(
  MdcDocument document,
) {
  final indexer = _HeadingIndexer()..reserveIds(document.nodes);
  final nodes = indexer.rewriteNodes(document.nodes);
  final indexed = identical(nodes, document.nodes)
      ? document
      : MdcDocument(nodes: nodes, frontmatter: document.frontmatter);
  return (document: indexed, outline: _buildOutline(indexer.headings));
}

final class _HeadingIndexer {
  final Set<String> _usedIds = <String>{};
  final Map<String, int> _nextSuffix = <String, int>{};
  final List<_Heading> headings = <_Heading>[];

  void reserveIds(Iterable<MdcNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case MdcText():
          break;
        case MdcElement(:final attributes, :final children):
          final id = attributes['id'];
          if (id != null && id.isNotEmpty) {
            _usedIds.add(id);
          }
          reserveIds(children);
        case MdcComponent(:final children, :final slots):
          reserveIds(children);
          for (final slot in slots.values) {
            reserveIds(slot.children);
          }
      }
    }
  }

  List<MdcNode> rewriteNodes(List<MdcNode> nodes) {
    List<MdcNode>? rewritten;
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final replacement = _rewriteNode(node);
      if (!identical(node, replacement)) {
        rewritten ??= nodes.toList(growable: false);
        rewritten[index] = replacement;
      }
    }
    return rewritten ?? nodes;
  }

  MdcNode _rewriteNode(MdcNode node) {
    return switch (node) {
      MdcText() => node,
      MdcElement() => _rewriteElement(node),
      MdcComponent() => _rewriteComponent(node),
    };
  }

  MdcElement _rewriteElement(MdcElement element) {
    final level = _headingLevel(element.tag);
    Map<String, String?>? attributes;
    if (level != null) {
      final title = _headingText(element.children);
      final explicitId = element.attributes['id'];
      final id = explicitId != null && explicitId.isNotEmpty
          ? explicitId
          : _uniqueId(_slug(title));
      if (explicitId == null || explicitId.isEmpty) {
        attributes = <String, String?>{...element.attributes, 'id': id};
      }
      headings.add(_Heading(id: id, title: title, level: level));
    }

    final children = rewriteNodes(element.children);
    if (attributes == null && identical(children, element.children)) {
      return element;
    }
    return MdcElement(
      element.tag,
      attributes: attributes ?? element.attributes,
      children: children,
    );
  }

  MdcComponent _rewriteComponent(MdcComponent component) {
    final children = rewriteNodes(component.children);
    Map<String, MdcSlot>? slots;
    for (final MapEntry(:key, :value) in component.slots.entries) {
      final slotChildren = rewriteNodes(value.children);
      if (!identical(slotChildren, value.children)) {
        slots ??= Map<String, MdcSlot>.of(component.slots);
        slots[key] = MdcSlot(
          properties: value.properties,
          children: slotChildren,
        );
      }
    }
    if (identical(children, component.children) && slots == null) {
      return component;
    }
    return MdcComponent(
      component.name,
      properties: component.properties,
      children: children,
      slots: slots ?? component.slots,
    );
  }

  String _uniqueId(String base) {
    var suffix = _nextSuffix[base] ?? 1;
    var candidate = suffix == 1 ? base : '$base-$suffix';
    while (_usedIds.contains(candidate)) {
      suffix++;
      candidate = '$base-$suffix';
    }
    _nextSuffix[base] = suffix + 1;
    _usedIds.add(candidate);
    return candidate;
  }
}

int? _headingLevel(String tag) {
  if (tag.length != 2 || tag.codeUnitAt(0) != 0x68) {
    return null;
  }
  final level = tag.codeUnitAt(1) - 0x30;
  return level >= 1 && level <= 6 ? level : null;
}

String _headingText(Iterable<MdcNode> nodes) {
  final text = StringBuffer();
  _appendText(nodes, text);
  return text.toString().replaceAll(_whitespace, ' ').trim();
}

void _appendText(Iterable<MdcNode> nodes, StringBuffer output) {
  for (final node in nodes) {
    switch (node) {
      case MdcText(:final value):
        output.write(value);
      case MdcElement(:final children):
        _appendText(children, output);
      case MdcComponent(:final children, :final slots):
        _appendText(children, output);
        for (final slot in slots.values) {
          _appendText(slot.children, output);
        }
    }
  }
}

String _slug(String title) {
  final separated = title.toLowerCase().replaceAll(_slugSeparators, '-');
  var start = 0;
  var end = separated.length;
  while (start < end && separated.codeUnitAt(start) == 0x2d) {
    start++;
  }
  while (end > start && separated.codeUnitAt(end - 1) == 0x2d) {
    end--;
  }
  return start == end ? 'section' : separated.substring(start, end);
}

List<MdcOutlineEntry> _buildOutline(List<_Heading> headings) {
  final roots = <_OutlineBuilder>[];
  final stack = <_OutlineBuilder>[];
  for (final heading in headings) {
    while (stack.isNotEmpty && stack.last.level >= heading.level) {
      stack.removeLast();
    }
    final item = _OutlineBuilder(heading);
    if (stack.isEmpty) {
      roots.add(item);
    } else {
      stack.last.children.add(item);
    }
    stack.add(item);
  }
  return List<MdcOutlineEntry>.unmodifiable(
    roots.map((_OutlineBuilder item) => item.freeze()),
  );
}

final class _Heading {
  const _Heading({required this.id, required this.title, required this.level});

  final String id;
  final String title;
  final int level;
}

final class _OutlineBuilder {
  _OutlineBuilder(_Heading heading)
    : id = heading.id,
      title = heading.title,
      level = heading.level;

  final String id;
  final String title;
  final int level;
  final List<_OutlineBuilder> children = <_OutlineBuilder>[];

  MdcOutlineEntry freeze() => MdcOutlineEntry(
    id: id,
    title: title,
    level: level,
    children: children.map((_OutlineBuilder item) => item.freeze()),
  );
}

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _slugSeparators = RegExp(
  r"""[\s!"#$%&'()*+,./:;<=>?@\[\\\]^_`{|}~\-\u2000-\u206f\u3000-\u303f\uff00-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65]+""",
);
