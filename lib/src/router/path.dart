import 'codec.dart';

/// Invalid syntax in a typed route path.
final class PathSyntaxException implements FormatException {
  /// Creates a path syntax error.
  const PathSyntaxException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final Object? source;

  @override
  final int? offset;

  @override
  String toString() => 'PathSyntaxException: $message';
}

sealed class _Part {
  const _Part();
}

final class _StaticPart extends _Part {
  const _StaticPart(this.value);

  final String value;
}

final class _ParameterPart extends _Part {
  const _ParameterPart(this.name);

  final String name;
}

final class _RestPart extends _Part {
  const _RestPart(this.name);

  final String name;
}

/// The reversible subset of Roux path syntax used by typed destinations.
final class PathTemplate {
  PathTemplate._(this.source, this._parts, this.parameterNames);

  /// Parses static segments, `:name`, and final `**:name` captures.
  factory PathTemplate.parse(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty || normalized == '/') {
      return PathTemplate._(source, const <_Part>[], const <String>{});
    }
    final text = normalized.startsWith('/')
        ? normalized.substring(1)
        : normalized;
    final path = text.endsWith('/') ? text.substring(0, text.length - 1) : text;
    final segments = path.split('/');
    final parts = <_Part>[];
    final names = <String>{};

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.isEmpty) {
        throw PathSyntaxException('Path contains an empty segment.', source);
      }
      if (segment.startsWith('**:')) {
        final name = segment.substring(3);
        _validateName(name, source, names);
        if (index != segments.length - 1) {
          throw PathSyntaxException(
            'A rest parameter must be the final segment.',
            source,
          );
        }
        parts.add(_RestPart(name));
        continue;
      }
      if (segment.startsWith(':')) {
        final name = segment.substring(1);
        _validateName(name, source, names);
        parts.add(_ParameterPart(name));
        continue;
      }
      if (segment.contains(':') ||
          segment.contains('*') ||
          segment.contains('(') ||
          segment.contains('{')) {
        throw PathSyntaxException(
          'Typed routes support only static, :name, and **:name segments.',
          source,
        );
      }
      parts.add(_StaticPart(segment));
    }

    return PathTemplate._(
      source,
      List<_Part>.of(parts, growable: false),
      Set<String>.of(names),
    );
  }

  /// The original local path.
  final String source;

  final List<_Part> _parts;

  /// Dynamic parameter names owned by this path.
  final Set<String> parameterNames;

  /// The local Roux pattern used while registering a complete branch.
  String get pattern => _parts
      .map((part) {
        return switch (part) {
          _StaticPart(:final value) => Uri.encodeComponent(value),
          _ParameterPart(:final name) => ':$name',
          _RestPart(:final name) => '**:$name',
        };
      })
      .join('/');

  /// Extracts only this route's decoded captures from a Roux match.
  Map<String, List<String>> captures(Map<String, String> values) {
    if (parameterNames.isEmpty) return const <String, List<String>>{};
    final captures = <String, List<String>>{};
    for (final part in _parts) {
      switch (part) {
        case _ParameterPart(:final name):
          final value = values[name];
          if (value != null) {
            captures[name] = <String>[Uri.decodeComponent(value)];
          }
        case _RestPart(:final name):
          final value = values[name];
          if (value != null && value.isNotEmpty) {
            captures[name] = value
                .split('/')
                .map(Uri.decodeComponent)
                .toList(growable: false);
          }
        case _StaticPart():
          break;
      }
    }
    return captures;
  }

  /// Number of source path segments consumed by this route.
  int consumedSegments(Map<String, String> values) {
    var count = 0;
    for (final part in _parts) {
      count += switch (part) {
        _RestPart(:final name) => values[name]?.split('/').length ?? 0,
        _ => 1,
      };
    }
    return count;
  }

  /// Builds decoded path segments from typed encoded parameters.
  List<String> build(Map<String, List<String>> parameters) {
    final names = parameters.keys.toSet();
    if (names.length != parameterNames.length ||
        !names.containsAll(parameterNames)) {
      throw ParameterFormatException(
        'Encoded path parameters $names do not match $parameterNames.',
      );
    }

    final segments = <String>[];
    for (final part in _parts) {
      switch (part) {
        case _StaticPart(:final value):
          segments.add(value);
        case _ParameterPart(:final name):
          final values = parameters[name]!;
          if (values.length != 1) {
            throw ParameterFormatException(
              'Path parameter "$name" must encode one segment.',
            );
          }
          segments.add(values.single);
        case _RestPart(:final name):
          final values = parameters[name]!;
          if (values.isEmpty) {
            throw ParameterFormatException(
              'Rest parameter "$name" cannot be empty.',
            );
          }
          segments.addAll(values);
      }
    }
    return segments;
  }

  static void _validateName(String name, String source, Set<String> names) {
    if (!_name.hasMatch(name)) {
      throw PathSyntaxException('Invalid parameter name "$name".', source);
    }
    if (!names.add(name)) {
      throw PathSyntaxException('Duplicate parameter name "$name".', source);
    }
  }
}

final RegExp _name = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');
