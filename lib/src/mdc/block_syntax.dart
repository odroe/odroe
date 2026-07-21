import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;

import 'markdown.dart';
import 'properties.dart';

/// Parses fenced MDC block components and their named slots.
final class MdcBlockSyntax extends markdown.BlockSyntax {
  /// Creates the block syntax.
  const MdcBlockSyntax();

  static final _pattern = RegExp(r'^:{2,}[A-Za-z]');

  @override
  RegExp get pattern => _pattern;

  @override
  bool canParse(markdown.BlockParser parser) =>
      _BlockOpening.tryParse(parser.current.content) != null;

  @override
  markdown.Node parse(markdown.BlockParser parser) {
    final opening = _BlockOpening.tryParse(parser.current.content)!;
    parser.advance();

    final lines = <markdown.Line>[];
    _CodeFence? codeFence;
    while (!parser.isDone) {
      final line = parser.current.content;
      if (codeFence != null) {
        lines.add(parser.current);
        if (codeFence.closes(line)) codeFence = null;
        parser.advance();
        continue;
      }
      codeFence = _CodeFence.tryOpen(line);
      if (codeFence == null && _isClosingFence(line, opening.fence)) break;
      lines.add(parser.current);
      parser.advance();
    }
    if (parser.isDone) {
      throw FormatException('Unclosed MDC component "${opening.name}".');
    }
    parser.advance();

    final yaml = _extractYamlProperties(lines);
    final properties = <String, Object?>{...opening.properties};
    for (final entry in yaml.properties.entries) {
      if (properties.containsKey(entry.key)) {
        throw FormatException(
          'Duplicate MDC component property "${entry.key}".',
        );
      }
      properties[entry.key] = entry.value;
    }

    final sections = _splitSlots(yaml.lines);
    final children = markdown.BlockParser(
      sections.defaultLines,
      parser.document,
    ).parseLines(parentSyntax: this);
    for (final entry in sections.slots.entries) {
      children.add(
        markdown.Element(
            mdcSlotTag,
            markdown.BlockParser(
              entry.value.lines,
              parser.document,
            ).parseLines(parentSyntax: this),
          )
          ..attributes[mdcNameAttribute] = entry.key
          ..attributes[mdcPropertiesAttribute] = jsonEncode(
            entry.value.properties,
          ),
      );
    }

    return markdown.Element(mdcComponentTag, children)
      ..attributes[mdcNameAttribute] = opening.name
      ..attributes[mdcPropertiesAttribute] = jsonEncode(properties);
  }
}

final class _BlockOpening {
  const _BlockOpening(this.fence, this.name, this.properties);

  final String fence;
  final String name;
  final Map<String, Object?> properties;

  static _BlockOpening? tryParse(String line) {
    var index = 0;
    while (index < line.length && line.codeUnitAt(index) == 58) {
      index++;
    }
    if (index < 2 ||
        index == line.length ||
        !isMdcNameStart(line.codeUnitAt(index))) {
      return null;
    }
    final fence = line.substring(0, index);
    final nameStart = index++;
    while (index < line.length && isMdcNamePart(line.codeUnitAt(index))) {
      index++;
    }
    final name = line.substring(nameStart, index);
    index = skipMdcWhitespace(line, index);

    var properties = const <String, Object?>{};
    if (index < line.length) {
      final attributes = readMdcDelimited(line, index, 123, 125);
      if (attributes == null ||
          skipMdcWhitespace(line, attributes.end) != line.length) {
        return null;
      }
      properties = parseMdcProperties(attributes.value);
    }
    return _BlockOpening(fence, name, properties);
  }
}

final class _SlotSections {
  const _SlotSections(this.defaultLines, this.slots);

  final List<markdown.Line> defaultLines;
  final Map<String, _SlotSource> slots;
}

final class _YamlProperties {
  const _YamlProperties(this.properties, this.lines);

  final Map<String, Object?> properties;
  final List<markdown.Line> lines;
}

final class _SlotSource {
  const _SlotSource(this.properties, this.lines);

  final Map<String, Object?> properties;
  final List<markdown.Line> lines;
}

final class _SlotOpening {
  const _SlotOpening(this.name, this.properties);

  final String name;
  final Map<String, Object?> properties;

  static _SlotOpening? tryParse(String line) {
    if (line.length < 2 || line.codeUnitAt(0) != 35) return null;
    var index = 1;
    if (!isMdcNameStart(line.codeUnitAt(index))) return null;
    final nameStart = index++;
    while (index < line.length && isMdcNamePart(line.codeUnitAt(index))) {
      index++;
    }
    final name = line.substring(nameStart, index);
    index = skipMdcWhitespace(line, index);

    var properties = const <String, Object?>{};
    if (index < line.length) {
      final attributes = readMdcDelimited(line, index, 123, 125);
      if (attributes == null ||
          skipMdcWhitespace(line, attributes.end) != line.length) {
        return null;
      }
      properties = parseMdcProperties(attributes.value);
    }
    return _SlotOpening(name, properties);
  }
}

_SlotSections _splitSlots(List<markdown.Line> lines) {
  final defaultLines = <markdown.Line>[];
  final slots = <String, _SlotSource>{};
  var currentLines = defaultLines;
  var hasExplicitDefault = false;
  final nestedFences = <String>[];
  _CodeFence? codeFence;

  for (final line in lines) {
    if (codeFence != null) {
      currentLines.add(line);
      if (codeFence.closes(line.content)) codeFence = null;
      continue;
    }
    codeFence = _CodeFence.tryOpen(line.content);
    if (codeFence != null) {
      currentLines.add(line);
      continue;
    }

    final opening = _BlockOpening.tryParse(line.content);
    if (opening != null) {
      nestedFences.add(opening.fence);
    } else if (nestedFences.isNotEmpty &&
        _isClosingFence(line.content, nestedFences.last)) {
      nestedFences.removeLast();
    }

    final slot = nestedFences.isEmpty
        ? _SlotOpening.tryParse(line.content)
        : null;
    if (slot != null) {
      if (slot.name == 'default') {
        if (hasExplicitDefault) {
          throw const FormatException('Duplicate MDC default slot.');
        }
        if (slot.properties.isNotEmpty) {
          throw const FormatException(
            'MDC default slots cannot declare properties.',
          );
        }
        hasExplicitDefault = true;
        currentLines = defaultLines;
        continue;
      }
      if (slots.containsKey(slot.name)) {
        throw FormatException('Duplicate MDC slot "${slot.name}".');
      }
      final source = _SlotSource(slot.properties, <markdown.Line>[]);
      slots[slot.name] = source;
      currentLines = source.lines;
      continue;
    }
    currentLines.add(line);
  }
  return _SlotSections(defaultLines, slots);
}

_YamlProperties _extractYamlProperties(List<markdown.Line> lines) {
  if (lines.isEmpty || lines.first.content.trimRight() != '---') {
    return _YamlProperties(const <String, Object?>{}, lines);
  }
  var end = 1;
  while (end < lines.length && lines[end].content.trimRight() != '---') {
    end++;
  }
  if (end == lines.length) {
    throw const FormatException('Unclosed MDC component YAML properties.');
  }
  return _YamlProperties(
    parseMdcYamlProperties(
      lines.sublist(1, end).map((line) => line.content).join('\n'),
    ),
    lines.sublist(end + 1),
  );
}

bool _isClosingFence(String line, String fence) => line.trim() == fence;

final class _CodeFence {
  const _CodeFence(this.character, this.length);

  final int character;
  final int length;

  static _CodeFence? tryOpen(String line) {
    var index = 0;
    while (index < line.length && index < 4 && line.codeUnitAt(index) == 32) {
      index++;
    }
    if (index > 3 || index == line.length) return null;
    final character = line.codeUnitAt(index);
    if (character != 96 && character != 126) return null;
    final start = index;
    while (index < line.length && line.codeUnitAt(index) == character) {
      index++;
    }
    final length = index - start;
    return length < 3 ? null : _CodeFence(character, length);
  }

  bool closes(String line) {
    var index = 0;
    while (index < line.length && index < 4 && line.codeUnitAt(index) == 32) {
      index++;
    }
    if (index > 3 || index == line.length) return false;
    final start = index;
    while (index < line.length && line.codeUnitAt(index) == character) {
      index++;
    }
    return index - start >= length && line.substring(index).trim().isEmpty;
  }
}
