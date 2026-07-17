import 'codec.dart';

/// An invalid route path declaration.
final class PathPatternException implements FormatException {
  /// Creates a path-pattern error.
  const PathPatternException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final Object? source;

  @override
  final int? offset;

  @override
  String toString() => 'PathPatternException: $message';
}

sealed class _PathPart {
  const _PathPart();

  int get rank;
}

final class _StaticPart extends _PathPart {
  const _StaticPart(this.value);

  final String value;

  @override
  int get rank => 3;
}

final class _ParameterPart extends _PathPart {
  const _ParameterPart(this.name);

  final String name;

  @override
  int get rank => 2;
}

final class _RestPart extends _PathPart {
  const _RestPart(this.name);

  final String name;

  @override
  int get rank => 1;
}

/// The internal result of matching part of a location.
final class PatternMatch {
  /// Creates a successful pattern match.
  const PatternMatch({required this.nextIndex, required this.parameters});

  /// The first path-segment index not consumed by the pattern.
  final int nextIndex;

  /// Raw dynamic segments captured by the pattern.
  final Map<String, List<String>> parameters;
}

/// A parsed Odroe path pattern.
final class RoutePattern {
  RoutePattern._(this.source, this._parts);

  /// Parses static, `[name]`, and `[...name]` path segments.
  factory RoutePattern.parse(String source) {
    final normalized = source.trim();
    if (normalized.isEmpty || normalized == '/') {
      return RoutePattern._(source, const <_PathPart>[]);
    }

    final text = normalized.startsWith('/')
        ? normalized.substring(1)
        : normalized;
    final withoutTrailingSlash = text.endsWith('/')
        ? text.substring(0, text.length - 1)
        : text;
    final rawParts = withoutTrailingSlash.split('/');
    final parts = <_PathPart>[];
    final names = <String>{};

    for (var index = 0; index < rawParts.length; index++) {
      final part = rawParts[index];
      if (part.isEmpty) {
        throw PathPatternException('Path contains an empty segment.', source);
      }
      if (part.startsWith('[...') && part.endsWith(']')) {
        final name = part.substring(4, part.length - 1);
        _validateName(name, source, names);
        if (index != rawParts.length - 1) {
          throw PathPatternException(
            'Catch-all segment "$part" must be the final segment.',
            source,
          );
        }
        parts.add(_RestPart(name));
        continue;
      }
      if (part.startsWith('[') && part.endsWith(']')) {
        final name = part.substring(1, part.length - 1);
        _validateName(name, source, names);
        parts.add(_ParameterPart(name));
        continue;
      }
      if (part.contains('[') || part.contains(']')) {
        throw PathPatternException(
          'Dynamic segment "$part" must occupy the complete segment.',
          source,
        );
      }
      parts.add(_StaticPart(part));
    }

    return RoutePattern._(source, List<_PathPart>.unmodifiable(parts));
  }

  /// The source path used to create the pattern.
  final String source;

  final List<_PathPart> _parts;

  /// Dynamic parameter names declared by this pattern.
  Set<String> get parameterNames => Set<String>.unmodifiable(
    _parts
        .whereType<_ParameterPart>()
        .map((part) => part.name)
        .followedBy(_parts.whereType<_RestPart>().map((part) => part.name)),
  );

  List<int> get _rank => List<int>.unmodifiable(
    _parts.map((part) => part.rank).followedBy(<int>[_parts.length]),
  );

  /// Matches this pattern at [start] in [segments].
  PatternMatch? match(List<String> segments, int start) {
    var index = start;
    final parameters = <String, List<String>>{};

    for (final part in _parts) {
      switch (part) {
        case _StaticPart(:final value):
          if (index >= segments.length || segments[index] != value) return null;
          index++;
        case _ParameterPart(:final name):
          if (index >= segments.length) return null;
          parameters[name] = <String>[segments[index]];
          index++;
        case _RestPart(:final name):
          if (index >= segments.length) return null;
          parameters[name] = segments.sublist(index);
          index = segments.length;
      }
    }

    return PatternMatch(nextIndex: index, parameters: parameters);
  }

  /// Builds encoded path segments from typed parameter output.
  List<String> build(Map<String, List<String>> parameters) {
    final actualNames = parameters.keys.toSet();
    if (!_sameSet(actualNames, parameterNames)) {
      throw ParameterFormatException(
        'Encoded path parameters $actualNames do not match '
        'declared parameters $parameterNames.',
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
              'Catch-all path parameter "$name" cannot be empty.',
            );
          }
          segments.addAll(values);
      }
    }
    return segments;
  }

  static void _validateName(String name, String source, Set<String> names) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw PathPatternException('Invalid parameter name "$name".', source);
    }
    if (!names.add(name)) {
      throw PathPatternException('Duplicate parameter name "$name".', source);
    }
  }

  static bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);
}

/// Orders more specific route patterns before less specific patterns.
int compareRoutePatterns(RoutePattern left, RoutePattern right) {
  final leftRank = left._rank;
  final rightRank = right._rank;
  final length = leftRank.length < rightRank.length
      ? leftRank.length
      : rightRank.length;
  for (var index = 0; index < length; index++) {
    final comparison = rightRank[index].compareTo(leftRank[index]);
    if (comparison != 0) return comparison;
  }
  return rightRank.length.compareTo(leftRank.length);
}
