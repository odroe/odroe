import 'dart:collection';

/// The behavior used when a URL contains invalid search values.
enum InvalidSearchBehavior {
  /// Use the route's default search state.
  fallback,

  /// Surface the parsing failure to the route error boundary.
  error,
}

/// An error produced while decoding path or search values.
final class ParameterFormatException implements FormatException {
  /// Creates a parameter format error.
  const ParameterFormatException(this.message, {this.source, this.offset});

  @override
  final String message;

  @override
  final Object? source;

  @override
  final int? offset;

  @override
  String toString() => 'ParameterFormatException: $message';
}

/// Read-only access to raw path parameters.
final class PathInput {
  /// Creates path input from decoded URI segments.
  PathInput(Map<String, List<String>> values)
    : _values = Map<String, List<String>>.unmodifiable(values);

  final Map<String, List<String>> _values;

  /// Returns the single string stored for [name].
  String requiredString(String name) {
    final values = _values[name];
    if (values == null || values.isEmpty) {
      throw ParameterFormatException('Missing path parameter "$name".');
    }
    if (values.length != 1) {
      throw ParameterFormatException(
        'Path parameter "$name" contains more than one segment.',
      );
    }
    return values.single;
  }

  /// Returns the integer stored for [name].
  int requiredInt(String name) {
    final value = requiredString(name);
    return int.tryParse(value) ??
        (throw ParameterFormatException(
          'Path parameter "$name" must be an integer.',
          source: value,
        ));
  }

  /// Returns the finite double stored for [name].
  double requiredDouble(String name) {
    final value = requiredString(name);
    final result = double.tryParse(value);
    if (result == null || !result.isFinite) {
      throw ParameterFormatException(
        'Path parameter "$name" must be a finite number.',
        source: value,
      );
    }
    return result;
  }

  /// Returns the boolean stored for [name].
  bool requiredBool(String name) {
    final value = requiredString(name);
    return switch (value) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => throw ParameterFormatException(
        'Path parameter "$name" must be true or false.',
        source: value,
      ),
    };
  }

  /// Returns all catch-all path segments stored for [name].
  List<String> segments(String name) {
    final values = _values[name];
    if (values == null || values.isEmpty) {
      throw ParameterFormatException('Missing path parameter "$name".');
    }
    return List<String>.unmodifiable(values);
  }
}

/// Collects encoded path parameters.
final class PathOutput {
  final Map<String, List<String>> _values = <String, List<String>>{};

  /// Writes a string path parameter.
  void string(String name, String value) => _write(name, <String>[value]);

  /// Writes an integer path parameter.
  void integer(String name, int value) => string(name, value.toString());

  /// Writes a finite double path parameter.
  void decimal(String name, double value) {
    if (!value.isFinite) {
      throw ParameterFormatException(
        'Path parameter "$name" must be a finite number.',
        source: value,
      );
    }
    string(name, value.toString());
  }

  /// Writes a boolean path parameter.
  void boolean(String name, bool value) => string(name, value.toString());

  /// Writes catch-all path segments.
  void segments(String name, Iterable<String> values) {
    final segments = List<String>.unmodifiable(values);
    if (segments.isEmpty) {
      throw ParameterFormatException(
        'Catch-all path parameter "$name" cannot be empty.',
      );
    }
    _write(name, segments);
  }

  void _write(String name, List<String> values) {
    if (_values.containsKey(name)) {
      throw ParameterFormatException(
        'Path parameter "$name" was encoded more than once.',
      );
    }
    _values[name] = values;
  }

  Map<String, List<String>> _take() =>
      Map<String, List<String>>.unmodifiable(_values);
}

/// A bidirectional typed path-parameter contract.
final class PathParams<P> {
  /// Creates an explicit runtime codec.
  const PathParams.codec({
    required P Function(PathInput input) decode,
    required void Function(P value, PathOutput output) encode,
  }) : _decode = decode,
       _encode = encode,
       isSchema = false;

  /// Declares a codec that the file-route compiler must generate.
  const PathParams.schema() : _decode = null, _encode = null, isSchema = true;

  final P Function(PathInput input)? _decode;
  final void Function(P value, PathOutput output)? _encode;

  /// Whether this contract still requires file-route compilation.
  final bool isSchema;

  /// Decodes raw values into [P].
  P decode(Map<String, List<String>> values) {
    final decode = _decode;
    if (decode == null) {
      throw StateError('PathParams.schema() has not been compiled.');
    }
    return decode(PathInput(values));
  }

  /// Encodes [value] into raw path segments.
  Map<String, List<String>> encode(P value) {
    final encode = _encode;
    if (encode == null) {
      throw StateError('PathParams.schema() has not been compiled.');
    }
    final output = PathOutput();
    encode(value, output);
    return output._take();
  }
}

/// Read-only access to a URI query multimap.
final class SearchInput {
  /// Creates search input from a decoded URI query multimap.
  SearchInput(Map<String, List<String>> values)
    : _values = Map<String, List<String>>.unmodifiable(values);

  final Map<String, List<String>> _values;
  final Set<String> _readKeys = <String>{};

  /// Returns a scalar query value, or `null` when it is absent.
  String? string(String name) {
    _readKeys.add(name);
    final values = _values[name];
    if (values == null || values.isEmpty) return null;
    if (values.length != 1) {
      throw ParameterFormatException(
        'Search parameter "$name" must contain one value.',
      );
    }
    return values.single;
  }

  /// Returns an integer query value, or `null` when it is absent.
  int? integer(String name) {
    final value = string(name);
    if (value == null) return null;
    return int.tryParse(value) ??
        (throw ParameterFormatException(
          'Search parameter "$name" must be an integer.',
          source: value,
        ));
  }

  /// Returns a finite double query value, or `null` when it is absent.
  double? decimal(String name) {
    final value = string(name);
    if (value == null) return null;
    final result = double.tryParse(value);
    if (result == null || !result.isFinite) {
      throw ParameterFormatException(
        'Search parameter "$name" must be a finite number.',
        source: value,
      );
    }
    return result;
  }

  /// Returns a boolean query value, or `null` when it is absent.
  bool? boolean(String name) {
    final value = string(name);
    if (value == null) return null;
    return switch (value) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => throw ParameterFormatException(
        'Search parameter "$name" must be true or false.',
        source: value,
      ),
    };
  }

  /// Returns every query value stored for [name].
  List<String> strings(
    String name, {
    Iterable<String> fallback = const <String>[],
  }) {
    _readKeys.add(name);
    return List<String>.unmodifiable(_values[name] ?? fallback);
  }

  Set<String> _takeReadKeys() => Set<String>.unmodifiable(_readKeys);
}

/// Collects encoded query values in canonical field order.
final class SearchOutput {
  final LinkedHashMap<String, List<String>> _values =
      LinkedHashMap<String, List<String>>();

  /// Writes a scalar string, omitting `null` and [omitIf].
  void string(String name, String? value, {String? omitIf}) {
    if (value == null || value == omitIf) return;
    _write(name, <String>[value]);
  }

  /// Writes an integer, omitting `null` and [omitIf].
  void integer(String name, int? value, {int? omitIf}) {
    if (value == null || value == omitIf) return;
    _write(name, <String>[value.toString()]);
  }

  /// Writes a finite double, omitting `null` and [omitIf].
  void decimal(String name, double? value, {double? omitIf}) {
    if (value == null || value == omitIf) return;
    if (!value.isFinite) {
      throw ParameterFormatException(
        'Search parameter "$name" must be a finite number.',
        source: value,
      );
    }
    _write(name, <String>[value.toString()]);
  }

  /// Writes a boolean, omitting `null` and [omitIf].
  void boolean(String name, bool? value, {bool? omitIf}) {
    if (value == null || value == omitIf) return;
    _write(name, <String>[value.toString()]);
  }

  /// Writes repeated query values, omitting [omitIf].
  void strings(
    String name,
    Iterable<String> values, {
    Iterable<String>? omitIf,
  }) {
    final result = List<String>.unmodifiable(values);
    if (result.isEmpty || _iterableEquals(result, omitIf)) return;
    _write(name, result);
  }

  void _write(String name, List<String> values) {
    if (_values.containsKey(name)) {
      throw ParameterFormatException(
        'Search parameter "$name" was encoded more than once.',
      );
    }
    _values[name] = values;
  }

  Map<String, List<String>> _take() =>
      Map<String, List<String>>.unmodifiable(_values);

  static bool _iterableEquals(List<String> value, Iterable<String>? other) {
    if (other == null) return false;
    final otherValues = other.toList(growable: false);
    if (value.length != otherValues.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (value[index] != otherValues[index]) return false;
    }
    return true;
  }
}

/// The result of decoding one route's search state.
final class DecodedSearch<S> {
  /// Creates a decoded search result.
  const DecodedSearch({required this.value, required this.keys, this.error});

  /// The canonical typed search state.
  final S value;

  /// Query keys owned by the route.
  final Set<String> keys;

  /// The recovered parsing error, when fallback behavior was used.
  final Object? error;
}

/// A bidirectional typed search-state contract.
final class SearchParams<S> {
  /// Creates an explicit runtime codec.
  factory SearchParams.codec({
    required Iterable<String> keys,
    required S defaults,
    required S Function(SearchInput input) decode,
    required void Function(S value, SearchOutput output) encode,
    InvalidSearchBehavior invalid = InvalidSearchBehavior.fallback,
  }) => SearchParams<S>._codec(
    keys: Set<String>.unmodifiable(keys),
    defaults: defaults,
    decode: decode,
    encode: encode,
    invalid: invalid,
  );

  SearchParams._codec({
    required Set<String> keys,
    required this.defaults,
    required S Function(SearchInput input) decode,
    required void Function(S value, SearchOutput output) encode,
    required this.invalid,
  }) : _keys = keys,
       _decode = decode,
       _encode = encode,
       isSchema = false;

  /// Declares a codec that the file-route compiler must generate.
  const SearchParams.schema({
    required this.defaults,
    this.invalid = InvalidSearchBehavior.fallback,
  }) : _keys = null,
       _decode = null,
       _encode = null,
       isSchema = true;

  /// The complete state used when the URL omits or invalidates values.
  final S defaults;

  /// The invalid-value policy.
  final InvalidSearchBehavior invalid;

  final Set<String>? _keys;
  final S Function(SearchInput input)? _decode;
  final void Function(S value, SearchOutput output)? _encode;

  /// Whether this contract still requires file-route compilation.
  final bool isSchema;

  /// Decodes a URI query multimap into canonical typed state.
  DecodedSearch<S> decode(Map<String, List<String>> values) {
    final decode = _decode;
    if (decode == null) {
      throw StateError('SearchParams.schema() has not been compiled.');
    }
    final input = SearchInput(values);
    try {
      final value = decode(input);
      _validateReads(input);
      return DecodedSearch<S>(value: value, keys: _keys!);
    } on ParameterFormatException catch (error) {
      _validateReads(input);
      if (invalid == InvalidSearchBehavior.error) rethrow;
      return DecodedSearch<S>(value: defaults, keys: _keys!, error: error);
    }
  }

  /// Encodes typed state into a canonical URI query multimap.
  Map<String, List<String>> encode(S value) {
    final encode = _encode;
    if (encode == null) {
      throw StateError('SearchParams.schema() has not been compiled.');
    }
    final output = SearchOutput();
    encode(value, output);
    final encoded = output._take();
    final undeclared = encoded.keys.toSet().difference(_keys!);
    if (undeclared.isNotEmpty) {
      throw StateError(
        'SearchParams.codec() encoded undeclared keys $undeclared.',
      );
    }
    return encoded;
  }

  void _validateReads(SearchInput input) {
    final undeclared = input._takeReadKeys().difference(_keys!);
    if (undeclared.isNotEmpty) {
      throw StateError(
        'SearchParams.codec() decoded undeclared keys $undeclared.',
      );
    }
  }
}

/// The absence of path parameters.
final class NoParams {
  /// Creates the singleton-compatible empty value.
  const NoParams();
}

/// The absence of typed search state.
final class NoSearch {
  /// Creates the singleton-compatible empty value.
  const NoSearch();
}

/// The absence of route loader data.
final class NoData {
  /// Creates the singleton-compatible empty value.
  const NoData();
}
