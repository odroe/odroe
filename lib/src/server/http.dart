// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// HTTP methods understood by routes and server functions.
enum HttpMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE'),
  options('OPTIONS'),
  head('HEAD'),
  connect('CONNECT'),
  trace('TRACE');

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
  Headers([Map<String, Iterable<String>> values = const {}]) {
    for (final entry in values.entries) {
      _values[entry.key.toLowerCase()] = List<String>.of(entry.value);
    }
  }

  factory Headers.single(Map<String, String> values) {
    final headers = Headers();
    for (final entry in values.entries) {
      headers.set(entry.key, entry.value);
    }
    return headers;
  }

  final Map<String, List<String>> _values = <String, List<String>>{};

  String? value(String name) {
    final values = _values[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.length == 1 ? values.first : values.join(', ');
  }

  Iterable<String> values(String name) =>
      _values[name.toLowerCase()] ?? const <String>[];

  Iterable<MapEntry<String, List<String>>> get entries => _values.entries;

  void set(String name, String value) {
    _values[name.toLowerCase()] = <String>[value];
  }

  void append(String name, String value) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add(value);
  }

  void remove(String name) => _values.remove(name.toLowerCase());

  void addAll(Headers other) {
    for (final entry in other._values.entries) {
      _values[entry.key] = List<String>.of(entry.value);
    }
  }

  bool contains(String name) => _values.containsKey(name.toLowerCase());

  Headers copy() => Headers(_values);
}

/// Platform-neutral incoming request.
final class ServerRequest {
  ServerRequest({
    required this.method,
    required this.uri,
    Headers? headers,
    Stream<List<int>>? body,
    this.cancelled,
  }) : headers = headers ?? Headers(),
       body = body ?? const Stream<List<int>>.empty();

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

  final HttpMethod method;
  final Uri uri;
  final Headers headers;
  final Stream<List<int>> body;

  /// Completes when the adapter observes client disconnection.
  final Future<void>? cancelled;

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

  Future<String> readText({
    int maxBytes = 10 * 1024 * 1024,
    Encoding encoding = utf8,
  }) async => encoding.decode(await readBytes(maxBytes: maxBytes));

  Future<Object?> readJson({int maxBytes = 10 * 1024 * 1024}) async {
    final text = await readText(maxBytes: maxBytes);
    return text.isEmpty ? null : jsonDecode(text);
  }
}

/// Platform-neutral outgoing response with streaming body support.
final class ServerResponse {
  ServerResponse({
    this.status = 200,
    this.reason,
    Headers? headers,
    Stream<List<int>>? body,
  }) : headers = headers ?? Headers(),
       body = body ?? const Stream<List<int>>.empty();

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

  factory ServerResponse.redirect(Uri location, {int status = 302}) =>
      ServerResponse(
        status: status,
        headers: Headers.single(<String, String>{
          'location': location.toString(),
        }),
      );

  final int status;
  final String? reason;
  final Headers headers;
  final Stream<List<int>> body;

  Future<Uint8List> readBytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<String> readText([Encoding encoding = utf8]) async =>
      encoding.decode(await readBytes());
}

/// Raised before buffering a request body beyond its configured limit.
final class PayloadTooLargeException implements Exception {
  const PayloadTooLargeException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Request body exceeds $maxBytes bytes.';
}
