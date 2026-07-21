import 'package:yaml/yaml.dart';

/// Parses one MDC property list into JSON-compatible Dart values.
Map<String, Object?> parseMdcProperties(String source) =>
    _PropertyScanner(source).parse();

/// Parses an MDC YAML property block into JSON-compatible Dart values.
Map<String, Object?> parseMdcYamlProperties(String source) {
  final value = _readYaml(source);
  if (value == null) return <String, Object?>{};
  if (value is! Map<String, Object?>) {
    throw const FormatException('MDC YAML properties must be a mapping.');
  }
  return value;
}

/// Reads a balanced MDC delimiter beginning at [start].
({String value, int end})? readMdcDelimited(
  String source,
  int start,
  int opening,
  int closing, {
  bool honorQuotes = true,
}) {
  if (start >= source.length || source.codeUnitAt(start) != opening) {
    return null;
  }
  final stack = <int>[closing];
  int? quote;
  var escaped = false;

  for (var index = start + 1; index < source.length; index++) {
    final character = source.codeUnitAt(index);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character == 92) {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (character == quote) {
        if (quote == 39 &&
            index + 1 < source.length &&
            source.codeUnitAt(index + 1) == 39) {
          index++;
        } else {
          quote = null;
        }
      }
      continue;
    }
    if (honorQuotes && (character == 34 || character == 39)) {
      quote = character;
      continue;
    }
    if (character == 123) {
      stack.add(125);
      continue;
    }
    if (character == 91) {
      stack.add(93);
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

/// Whether [codeUnit] can begin an MDC name.
bool isMdcNameStart(int codeUnit) =>
    codeUnit >= 65 && codeUnit <= 90 ||
    codeUnit >= 97 && codeUnit <= 122 ||
    codeUnit == 95;

/// Whether [codeUnit] can continue an MDC name.
bool isMdcNamePart(int codeUnit) =>
    isMdcNameStart(codeUnit) ||
    codeUnit >= 48 && codeUnit <= 57 ||
    codeUnit == 45;

/// Whether [codeUnit] is ASCII whitespace accepted by MDC syntax.
bool isMdcWhitespace(int codeUnit) =>
    codeUnit == 32 || codeUnit == 9 || codeUnit == 13 || codeUnit == 10;

/// Skips MDC whitespace in [source] beginning at [index].
int skipMdcWhitespace(String source, int index) {
  while (index < source.length && isMdcWhitespace(source.codeUnitAt(index))) {
    index++;
  }
  return index;
}

final class _PropertyScanner {
  _PropertyScanner(this.source);

  final String source;
  var index = 0;

  Map<String, Object?> parse() {
    final result = <String, Object?>{};
    while (true) {
      index = skipMdcWhitespace(source, index);
      if (index == source.length) return result;

      final character = source.codeUnitAt(index);
      if (character == 35) {
        index++;
        _put(result, 'id', _readToken('id shorthand'));
        continue;
      }
      if (character == 46) {
        index++;
        _put(result, 'class', _readToken('class shorthand'));
        continue;
      }
      if (character == 58 || character == 64) {
        throw const FormatException(
          'MDC bindings, events, and directives are not executable syntax.',
        );
      }

      final key = _readKey();
      if (key.startsWith('v-')) {
        throw const FormatException('Vue directives are not MDC properties.');
      }
      index = skipMdcWhitespace(source, index);
      if (index == source.length || source.codeUnitAt(index) != 61) {
        _put(result, key, true);
        continue;
      }
      index++;
      index = skipMdcWhitespace(source, index);
      if (index == source.length) {
        throw FormatException('Missing value for MDC property "$key".');
      }
      _put(result, key, _readValue());
    }
  }

  String _readKey() {
    if (!isMdcNameStart(source.codeUnitAt(index))) {
      throw FormatException('Invalid MDC property at character ${index + 1}.');
    }
    final start = index++;
    while (index < source.length && isMdcNamePart(source.codeUnitAt(index))) {
      index++;
    }
    return source.substring(start, index);
  }

  String _readToken(String description) {
    final start = index;
    while (index < source.length && isMdcNamePart(source.codeUnitAt(index))) {
      index++;
    }
    if (start == index) throw FormatException('Empty MDC $description.');
    return source.substring(start, index);
  }

  Object? _readValue() {
    final start = index;
    final first = source.codeUnitAt(index);
    if (first == 34 || first == 39) {
      final quote = source.codeUnitAt(index++);
      var escaped = false;
      while (index < source.length) {
        final character = source.codeUnitAt(index++);
        if (escaped) {
          escaped = false;
        } else if (character == 92) {
          escaped = true;
        } else if (character == quote) {
          if (quote == 39 &&
              index < source.length &&
              source.codeUnitAt(index) == 39) {
            index++;
            continue;
          }
          return _readYaml(source.substring(start, index));
        }
      }
      throw const FormatException('Unclosed quoted MDC property value.');
    }
    if (first == 91 || first == 123) {
      final value = readMdcDelimited(
        source,
        index,
        first,
        first == 91 ? 93 : 125,
      );
      if (value == null) {
        throw const FormatException('Unclosed MDC property value.');
      }
      index = value.end;
      return _readYaml(source.substring(start, index));
    }
    while (index < source.length &&
        !isMdcWhitespace(source.codeUnitAt(index))) {
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
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException('MDC numeric values must be finite.');
    }
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
