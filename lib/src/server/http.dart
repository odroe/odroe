import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// HTTP methods understood by routes and server functions.
enum HttpMethod {
  /// Retrieves a resource.
  get('GET'),

  /// Creates or invokes a resource.
  post('POST'),

  /// Replaces a resource.
  put('PUT'),

  /// Partially updates a resource.
  patch('PATCH'),

  /// Deletes a resource.
  delete('DELETE'),

  /// Describes supported request options.
  options('OPTIONS'),

  /// Retrieves response headers without a body.
  head('HEAD'),

  /// Opens a network tunnel.
  connect('CONNECT'),

  /// Echoes a request for diagnostics.
  trace('TRACE');

  /// Creates a method with its HTTP wire name.
  const HttpMethod(this.wire);

  /// Upper-case wire representation.
  final String wire;

  /// Parses an HTTP method case-insensitively.
  factory HttpMethod.parse(String value) {
    return switch (value.toUpperCase()) {
      'GET' => get,
      'POST' => post,
      'PUT' => put,
      'PATCH' => patch,
      'DELETE' => delete,
      'OPTIONS' => options,
      'HEAD' => head,
      'CONNECT' => connect,
      'TRACE' => trace,
      _ => throw FormatException('Unsupported HTTP method: $value'),
    };
  }
}

/// Case-insensitive, multi-value HTTP headers.
final class Headers {
  /// Creates headers from zero or more values per name.
  Headers([Map<String, Iterable<String>> values = const {}]) {
    for (final entry in values.entries) {
      _values[entry.key.toLowerCase()] = List<String>.of(entry.value);
    }
  }

  /// Creates headers containing one value per name.
  factory Headers.single(Map<String, String> values) {
    final headers = Headers();
    for (final entry in values.entries) {
      headers.set(entry.key, entry.value);
    }
    return headers;
  }

  final Map<String, List<String>> _values = <String, List<String>>{};

  /// Returns all values for [name] joined for an HTTP header line.
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.length == 1 ? values.first : values.join(', ');
  }

  /// Returns the individual values for [name].
  Iterable<String> values(String name) =>
      _values[name.toLowerCase()] ?? const <String>[];

  /// Iterates over normalized names and their values.
  Iterable<MapEntry<String, List<String>>> get entries => _values.entries;

  /// Replaces [name] with one [value].
  void set(String name, String value) {
    _values[name.toLowerCase()] = <String>[value];
  }

  /// Appends [value] to [name].
  void append(String name, String value) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add(value);
  }

  /// Removes [name].
  void remove(String name) => _values.remove(name.toLowerCase());

  /// Replaces matching names with values from [other].
  void addAll(Headers other) {
    for (final entry in other._values.entries) {
      _values[entry.key] = List<String>.of(entry.value);
    }
  }

  /// Whether [name] is present.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// Creates an independent copy.
  Headers copy() => Headers(_values);
}

/// Platform-neutral incoming request.
final class ServerRequest {
  /// Creates a request from its method, URI, headers, and body stream.
  ServerRequest({
    required this.method,
    required this.uri,
    Headers? headers,
    Stream<List<int>>? body,
    this.cancelled,
  }) : headers = headers ?? Headers(),
       body = body ?? const Stream<List<int>>.empty();

  /// Creates a request whose body is already buffered.
  factory ServerRequest.bytes({
    required HttpMethod method,
    required Uri uri,
    Headers? headers,
    List<int> body = const <int>[],
  }) => ServerRequest(
    method: method,
    uri: uri,
    headers: headers,
    body: Stream<List<int>>.value(body),
  );

  /// The request method.
  final HttpMethod method;

  /// The requested URI.
  final Uri uri;

  /// The request headers.
  final Headers headers;

  /// The request body chunks.
  final Stream<List<int>> body;

  /// Completes when the adapter observes client disconnection.
  final Future<void>? cancelled;

  /// Reads and buffers the body, up to [maxBytes].
  Future<Uint8List> readBytes({int maxBytes = 10 * 1024 * 1024}) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in body) {
      length += chunk.length;
      if (length > maxBytes) {
        throw PayloadTooLargeException(maxBytes);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Reads the body as text using [encoding].
  Future<String> readText({
    int maxBytes = 10 * 1024 * 1024,
    Encoding encoding = utf8,
  }) async => encoding.decode(await readBytes(maxBytes: maxBytes));

  /// Reads and decodes a JSON body.
  Future<Object?> readJson({int maxBytes = 10 * 1024 * 1024}) async {
    final text = await readText(maxBytes: maxBytes);
    return text.isEmpty ? null : jsonDecode(text);
  }
}

/// Platform-neutral outgoing response with streaming body support.
final class ServerResponse {
  /// Creates a streaming response.
  ServerResponse({
    this.status = 200,
    this.reason,
    Headers? headers,
    Stream<List<int>>? body,
  }) : headers = headers ?? Headers(),
       body = body ?? const Stream<List<int>>.empty();

  /// Creates a response from buffered bytes.
  factory ServerResponse.bytes(
    List<int> bytes, {
    int status = 200,
    String? contentType,
    Headers? headers,
  }) {
    final resolved = headers?.copy() ?? Headers();
    if (contentType != null) resolved.set('content-type', contentType);
    resolved.set('content-length', '${bytes.length}');
    return ServerResponse(
      status: status,
      headers: resolved,
      body: Stream<List<int>>.value(bytes),
    );
  }

  /// Creates a plain-text response.
  factory ServerResponse.text(
    String text, {
    int status = 200,
    String contentType = 'text/plain; charset=utf-8',
    Headers? headers,
  }) => ServerResponse.bytes(
    utf8.encode(text),
    status: status,
    contentType: contentType,
    headers: headers,
  );

  /// Creates an HTML response.
  factory ServerResponse.html(
    String html, {
    int status = 200,
    Headers? headers,
  }) => ServerResponse.text(
    html,
    status: status,
    contentType: 'text/html; charset=utf-8',
    headers: headers,
  );

  /// Creates a JSON response.
  factory ServerResponse.json(
    Object? value, {
    int status = 200,
    Headers? headers,
  }) => ServerResponse.bytes(
    utf8.encode(jsonEncode(value)),
    status: status,
    contentType: 'application/json; charset=utf-8',
    headers: headers,
  );

  /// Creates a redirect response.
  factory ServerResponse.redirect(Uri location, {int status = 302}) =>
      ServerResponse(
        status: status,
        headers: Headers.single(<String, String>{
          'location': location.toString(),
        }),
      );

  /// The HTTP status code.
  final int status;

  /// The optional HTTP reason phrase.
  final String? reason;

  /// The response headers.
  final Headers headers;

  /// The response body chunks.
  final Stream<List<int>> body;

  /// Reads and buffers the complete response body.
  Future<Uint8List> readBytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Reads the complete response body as text.
  Future<String> readText([Encoding encoding = utf8]) async =>
      encoding.decode(await readBytes());
}

/// Raised before buffering a request body beyond its configured limit.
final class PayloadTooLargeException implements Exception {
  /// Creates an exception for the enforced [maxBytes].
  const PayloadTooLargeException(this.maxBytes);

  /// The maximum accepted body size.
  final int maxBytes;

  @override
  String toString() => 'Request body exceeds $maxBytes bytes.';
}
