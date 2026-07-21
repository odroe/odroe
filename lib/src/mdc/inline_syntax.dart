import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;

import 'markdown.dart';
import 'properties.dart';

/// Creates the stateless MDC inline syntaxes for one Markdown document.
List<markdown.InlineSyntax> createMdcInlineSyntaxes() =>
    <markdown.InlineSyntax>[
      _MdcInlineComponentSyntax(),
      _MdcSpanSyntax(),
      _MdcAttributeSyntax(),
    ];

final class _MdcInlineComponentSyntax extends markdown.InlineSyntax {
  _MdcInlineComponentSyntax() : super(r':', startCharacter: 58);

  @override
  bool tryMatch(markdown.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final invocation = _InlineInvocation.tryParse(parser.source, start);
    if (invocation == null) return false;

    parser.writeText();
    parser.addNode(
      markdown.Element(
          mdcComponentTag,
          invocation.content == null
              ? const <markdown.Node>[]
              : parser.document.parseInline(invocation.content!),
        )
        ..attributes[mdcNameAttribute] = invocation.name
        ..attributes[mdcPropertiesAttribute] = jsonEncode(
          invocation.properties,
        ),
    );
    parser.consume(invocation.end - start);
    return true;
  }

  @override
  bool onMatch(markdown.InlineParser parser, Match match) => false;
}

final class _MdcSpanSyntax extends markdown.InlineSyntax {
  _MdcSpanSyntax() : super(r'\[', startCharacter: 91);

  @override
  bool tryMatch(markdown.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final content = readMdcDelimited(
      parser.source,
      start,
      91,
      93,
      honorQuotes: false,
      skipCodeSpans: true,
    );
    if (content == null || content.end >= parser.source.length) return false;
    final attributes = readMdcDelimited(parser.source, content.end, 123, 125);
    if (attributes == null) return false;

    parser.writeText();
    parser.addNode(
      markdown.Element('span', parser.document.parseInline(content.value))
        ..attributes[mdcPropertiesAttribute] = jsonEncode(
          parseMdcProperties(attributes.value),
        ),
    );
    parser.consume(attributes.end - start);
    return true;
  }

  @override
  bool onMatch(markdown.InlineParser parser, Match match) => false;
}

final class _MdcAttributeSyntax extends markdown.InlineSyntax {
  _MdcAttributeSyntax() : super(r'\{', startCharacter: 123);

  @override
  bool tryMatch(markdown.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final attributes = readMdcDelimited(parser.source, start, 123, 125);
    if (attributes == null ||
        !_looksLikeElementAttributes(
          attributes.value,
          source: parser.source,
          start: start,
        )) {
      return false;
    }

    parser.writeText();
    parser.addNode(
      markdown.Element.empty(mdcAttributeTag)
        ..attributes[mdcPropertiesAttribute] = jsonEncode(
          parseMdcProperties(attributes.value),
        ),
    );
    parser.consume(attributes.end - start);
    return true;
  }

  @override
  bool onMatch(markdown.InlineParser parser, Match match) => false;
}

bool _looksLikeElementAttributes(
  String attributes, {
  required String source,
  required int start,
}) {
  final value = attributes.trimLeft();
  if (value.isEmpty) return false;
  final first = value.codeUnitAt(0);
  if (first == 35 || first == 46) return true;
  if (!value.contains('=') || start == 0) return false;
  final previous = source.codeUnitAt(start - 1);
  return switch (previous) {
    0x29 || 0x2a || 0x3e || 0x5d || 0x5f || 0x60 || 0x7e => true,
    _ => false,
  };
}

final class _InlineInvocation {
  const _InlineInvocation({
    required this.name,
    required this.content,
    required this.properties,
    required this.end,
  });

  final String name;
  final String? content;
  final Map<String, Object?> properties;
  final int end;

  static _InlineInvocation? tryParse(String source, int start) {
    if (start >= source.length || source.codeUnitAt(start) != 58) return null;
    var index = start + 1;
    if (index >= source.length || !isMdcNameStart(source.codeUnitAt(index))) {
      return null;
    }
    final nameStart = index++;
    while (index < source.length && isMdcNamePart(source.codeUnitAt(index))) {
      index++;
    }
    final name = source.substring(nameStart, index);

    String? content;
    if (index < source.length && source.codeUnitAt(index) == 91) {
      final value = readMdcDelimited(
        source,
        index,
        91,
        93,
        honorQuotes: false,
        skipCodeSpans: true,
      );
      if (value == null) return null;
      content = value.value;
      index = value.end;
    }

    var properties = const <String, Object?>{};
    var hasProperties = false;
    if (index < source.length && source.codeUnitAt(index) == 123) {
      final value = readMdcDelimited(source, index, 123, 125);
      if (value == null) return null;
      properties = parseMdcProperties(value.value);
      hasProperties = true;
      index = value.end;
    }
    if (content == null && !hasProperties) return null;

    return _InlineInvocation(
      name: name,
      content: content,
      properties: properties,
      end: index,
    );
  }
}
