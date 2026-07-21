import 'dart:convert';

import 'package:markdown/markdown.dart' as markdown;
import 'package:yaml/yaml.dart';

import 'ast.dart';

const _componentTag = 'x-odroe-mdc-component';
const _slotTag = 'x-odroe-mdc-slot';
const _attributeTag = 'x-odroe-mdc-attributes';
const _nameAttribute = 'data-mdc-name';
const _propertiesAttribute = 'data-mdc-properties';

/// Parses an MDC body after frontmatter has been removed.
///
/// This is internal package plumbing shared with [MdcParser] without using
/// `part` libraries. Applications should use [MdcParser.parse].
List<MdcNode> parseMdcBody(String source) {
  final extension = markdown.ExtensionSet(
    markdown.ExtensionSet.gitHubFlavored.blockSyntaxes,
    <markdown.InlineSyntax>[
      for (final syntax in markdown.ExtensionSet.gitHubFlavored.inlineSyntaxes)
        if (syntax is! markdown.InlineHtmlSyntax) syntax,
    ],
  );
  final document = markdown.Document(
    blockSyntaxes: const <markdown.BlockSyntax>[_MdcBlockSyntax()],
    inlineSyntaxes: <markdown.InlineSyntax>[
      _MdcInlineComponentSyntax(),
      _MdcSpanSyntax(),
      _MdcAttributeSyntax(),
    ],
    extensionSet: extension,
    encodeHtml: false,
  );
  return _convertRoot(document.parse(source));
}

final class _MdcBlockSyntax extends markdown.BlockSyntax {
  const _MdcBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^:{2,}[A-Za-z]');

  @override
  bool canParse(markdown.BlockParser parser) =>
      _BlockOpening.tryParse(parser.current.content) != null;

  @override
  markdown.Node parse(markdown.BlockParser parser) {
    final opening = _BlockOpening.tryParse(parser.current.content)!;
    final openingLine = parser.lines.indexOf(parser.current) + 1;
    parser.advance();

    final lines = <markdown.Line>[];
    while (!parser.isDone &&
        !_isClosingFence(parser.current.content, opening.fence)) {
      lines.add(parser.current);
      parser.advance();
    }
    if (parser.isDone) {
      throw FormatException(
        'Unclosed MDC component "${opening.name}" opened on line '
        '$openingLine.',
      );
    }
    parser.advance();

    final sections = _splitSlots(lines);
    final children = markdown.BlockParser(
      sections.defaultLines,
      parser.document,
    ).parseLines(parentSyntax: this);
    for (final entry in sections.slots.entries) {
      children.add(
        markdown.Element(
            _slotTag,
            markdown.BlockParser(
              entry.value.lines,
              parser.document,
            ).parseLines(parentSyntax: this),
          )
          ..attributes[_nameAttribute] = entry.key
          ..attributes[_propertiesAttribute] = jsonEncode(
            entry.value.properties,
          ),
      );
    }

    return markdown.Element(_componentTag, children)
      ..attributes[_nameAttribute] = opening.name
      ..attributes[_propertiesAttribute] = jsonEncode(opening.properties);
  }
}

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
          _componentTag,
          invocation.content == null
              ? const <markdown.Node>[]
              : parser.document.parseInline(invocation.content!),
        )
        ..attributes[_nameAttribute] = invocation.name
        ..attributes[_propertiesAttribute] = jsonEncode(invocation.properties),
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
    final content = _readDelimited(parser.source, start, '[', ']');
    if (content == null || content.end >= parser.source.length) return false;
    final attributes = _readDelimited(parser.source, content.end, '{', '}');
    if (attributes == null) return false;

    parser.writeText();
    parser.addNode(
      markdown.Element('span', parser.document.parseInline(content.value))
        ..attributes[_propertiesAttribute] = jsonEncode(
          _parseProperties(attributes.value),
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
    final attributes = _readDelimited(parser.source, start, '{', '}');
    if (attributes == null) return false;

    parser.writeText();
    parser.addNode(
      markdown.Element.empty(_attributeTag)
        ..attributes[_propertiesAttribute] = jsonEncode(
          _parseProperties(attributes.value),
        ),
    );
    parser.consume(attributes.end - start);
    return true;
  }

  @override
  bool onMatch(markdown.InlineParser parser, Match match) => false;
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
    if (index < 2 || index == line.length || !_isNameStart(line[index])) {
      return null;
    }
    final fence = line.substring(0, index);
    final nameStart = index;
    index++;
    while (index < line.length && _isNamePart(line[index])) {
      index++;
    }
    final name = line.substring(nameStart, index);
    index = _skipWhitespace(line, index);

    var properties = const <String, Object?>{};
    if (index < line.length) {
      final attributes = _readDelimited(line, index, '{', '}');
      if (attributes == null ||
          _skipWhitespace(line, attributes.end) != line.length) {
        return null;
      }
      properties = _parseProperties(attributes.value);
    }
    return _BlockOpening(fence, name, properties);
  }
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
    if (index >= source.length || !_isNameStart(source[index])) return null;
    final nameStart = index;
    index++;
    while (index < source.length && _isNamePart(source[index])) {
      index++;
    }
    final name = source.substring(nameStart, index);

    String? content;
    if (index < source.length && source[index] == '[') {
      final value = _readDelimited(source, index, '[', ']');
      if (value == null) return null;
      content = value.value;
      index = value.end;
    }

    var properties = const <String, Object?>{};
    if (index < source.length && source[index] == '{') {
      final value = _readDelimited(source, index, '{', '}');
      if (value == null) return null;
      properties = _parseProperties(value.value);
      index = value.end;
    }
    if (content == null && properties.isEmpty) return null;

    return _InlineInvocation(
      name: name,
      content: content,
      properties: properties,
      end: index,
    );
  }
}

final class _SlotSections {
  const _SlotSections(this.defaultLines, this.slots);

  final List<markdown.Line> defaultLines;
  final Map<String, _SlotSource> slots;
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
    if (line.isEmpty || line[0] != '#' || line.length == 1) return null;
    var index = 1;
    if (!_isNameStart(line[index])) return null;
    final nameStart = index;
    index++;
    while (index < line.length && _isNamePart(line[index])) {
      index++;
    }
    final name = line.substring(nameStart, index);
    index = _skipWhitespace(line, index);

    var properties = const <String, Object?>{};
    if (index < line.length) {
      final attributes = _readDelimited(line, index, '{', '}');
      if (attributes == null ||
          _skipWhitespace(line, attributes.end) != line.length) {
        return null;
      }
      properties = _parseProperties(attributes.value);
    }
    return _SlotOpening(name, properties);
  }
}

_SlotSections _splitSlots(List<markdown.Line> lines) {
  final defaultLines = <markdown.Line>[];
  final slots = <String, _SlotSource>{};
  _SlotSource? current;
  final nestedFences = <String>[];

  for (final line in lines) {
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
      if (slots.containsKey(slot.name)) {
        throw FormatException('Duplicate MDC slot "${slot.name}".');
      }
      current = _SlotSource(slot.properties, <markdown.Line>[]);
      slots[slot.name] = current;
      continue;
    }
    (current?.lines ?? defaultLines).add(line);
  }
  return _SlotSections(defaultLines, slots);
}

bool _isClosingFence(String line, String fence) => line.trim() == fence;

({String value, int end})? _readDelimited(
  String source,
  int start,
  String opening,
  String closing,
) {
  if (start >= source.length || source[start] != opening) return null;
  final stack = <String>[closing];
  String? quote;
  var escaped = false;

  for (var index = start + 1; index < source.length; index++) {
    final character = source[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character == r'\') {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (character == quote) quote = null;
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
      continue;
    }
    if (character == '{') {
      stack.add('}');
      continue;
    }
    if (character == '[') {
      stack.add(']');
      continue;
    }
    if (character == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) {
        return (value: source.substring(start + 1, index), end: index + 1);
      }
    }
  }
  return null;
}

Map<String, Object?> _parseProperties(String source) {
  final scanner = _PropertyScanner(source);
  return scanner.parse();
}

final class _PropertyScanner {
  _PropertyScanner(this.source);

  final String source;
  var index = 0;

  Map<String, Object?> parse() {
    final result = <String, Object?>{};
    while (true) {
      index = _skipWhitespace(source, index);
      if (index == source.length) return result;

      if (source[index] == '#') {
        index++;
        _put(result, 'id', _readToken('id shorthand'));
        continue;
      }
      if (source[index] == '.') {
        index++;
        _put(result, 'class', _readToken('class shorthand'));
        continue;
      }
      if (source[index] == ':' || source[index] == '@') {
        throw const FormatException(
          'MDC bindings, events, and directives are not executable syntax.',
        );
      }

      final key = _readKey();
      if (key.startsWith('v-')) {
        throw const FormatException('Vue directives are not MDC properties.');
      }
      index = _skipWhitespace(source, index);
      if (index == source.length || source[index] != '=') {
        _put(result, key, true);
        continue;
      }
      index++;
      index = _skipWhitespace(source, index);
      if (index == source.length) {
        throw FormatException('Missing value for MDC property "$key".');
      }
      _put(result, key, _readValue());
    }
  }

  String _readKey() {
    if (!_isNameStart(source[index])) {
      throw FormatException('Invalid MDC property at character ${index + 1}.');
    }
    final start = index++;
    while (index < source.length && _isPropertyPart(source[index])) {
      index++;
    }
    return source.substring(start, index);
  }

  String _readToken(String description) {
    final start = index;
    while (index < source.length && _isNamePart(source[index])) {
      index++;
    }
    if (start == index) {
      throw FormatException('Empty MDC $description.');
    }
    return source.substring(start, index);
  }

  Object? _readValue() {
    final start = index;
    if (source[index] == '"' || source[index] == "'") {
      final quote = source[index++];
      var escaped = false;
      while (index < source.length) {
        final character = source[index++];
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          return _readYaml(source.substring(start, index));
        }
      }
      throw const FormatException('Unclosed quoted MDC property value.');
    }
    if (source[index] == '[' || source[index] == '{') {
      final opening = source[index];
      final value = _readDelimited(
        source,
        index,
        opening,
        opening == '[' ? ']' : '}',
      );
      if (value == null) {
        throw const FormatException('Unclosed MDC property value.');
      }
      index = value.end;
      return _readYaml(source.substring(start, index));
    }
    while (index < source.length && !_isWhitespace(source[index])) {
      index++;
    }
    return _readYaml(source.substring(start, index));
  }

  void _put(Map<String, Object?> result, String key, Object? value) {
    if (key == 'class') {
      final current = result[key];
      if (current is String) {
        result[key] = '$current $value';
        return;
      }
    }
    if (result.containsKey(key)) {
      throw FormatException('Duplicate MDC property "$key".');
    }
    result[key] = value;
  }
}

Object? _readYaml(String source) {
  final Object? value;
  try {
    value = loadYaml(source);
  } on YamlException catch (error) {
    throw FormatException('Invalid MDC property value: ${error.message}');
  }
  return _normalizeProperty(value);
}

Object? _normalizeProperty(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final MapEntry(:key, :value) in value.entries) {
      if (key is! String) {
        throw const FormatException(
          'MDC object property keys must be strings.',
        );
      }
      result[key] = _normalizeProperty(value);
    }
    return result;
  }
  if (value is Iterable<Object?>) {
    return <Object?>[for (final item in value) _normalizeProperty(item)];
  }
  throw FormatException('Unsupported MDC property value ${value.runtimeType}.');
}

List<MdcNode> _convertRoot(List<markdown.Node> nodes) {
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
  markdown.Element node when node.tag == _componentTag => _convertComponent(
    node,
  ),
  markdown.Element node => _convertElement(node),
  _ => throw StateError('Unsupported Markdown node ${node.runtimeType}.'),
};

MdcComponent _convertComponent(markdown.Element element) {
  final children = <MdcNode>[];
  final slots = <String, MdcSlot>{};
  for (final child in element.children ?? const <markdown.Node>[]) {
    if (child is markdown.Element && child.tag == _slotTag) {
      final name = child.attributes[_nameAttribute]!;
      slots[name] = MdcSlot(
        properties: _decodeProperties(child),
        children: _convertRoot(child.children ?? const <markdown.Node>[]),
      );
    } else {
      children.add(_convertNode(child));
    }
  }
  return MdcComponent(
    element.attributes[_nameAttribute]!,
    properties: _decodeProperties(element),
    children: children,
    slots: slots,
  );
}

MdcElement _convertElement(markdown.Element element) {
  final attributes = <String, String?>{
    for (final entry in element.attributes.entries)
      if (entry.key != _propertiesAttribute) entry.key: entry.value,
  };
  final children = <MdcNode>[];
  final rawChildren = element.children ?? const <markdown.Node>[];
  for (var index = 0; index < rawChildren.length; index++) {
    final child = rawChildren[index];
    if (child is markdown.Element && child.tag == _attributeTag) {
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
  if (element.attributes[_propertiesAttribute] != null) {
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
  final source = element.attributes[_propertiesAttribute];
  if (source == null) return const <String, Object?>{};
  return (jsonDecode(source) as Map<String, Object?>);
}

bool _isNameStart(String character) => RegExp(r'[A-Za-z_]').hasMatch(character);

bool _isNamePart(String character) =>
    RegExp(r'[A-Za-z0-9_-]').hasMatch(character);

bool _isPropertyPart(String character) =>
    RegExp(r'[A-Za-z0-9_-]').hasMatch(character);

bool _isWhitespace(String character) =>
    character == ' ' ||
    character == '\t' ||
    character == '\r' ||
    character == '\n';

int _skipWhitespace(String source, int index) {
  while (index < source.length && _isWhitespace(source[index])) {
    index++;
  }
  return index;
}
