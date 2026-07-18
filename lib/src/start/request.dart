// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// HTTP methods understood by Start routes and server functions.
enum StartMethod {
  get,
  post,
  put,
  patch,
  delete,
  options,
  head,
  connect,
  trace;

  /// Parses an HTTP method case-insensitively.
  factory StartMethod.parse(String value) {
    final normalized = value.toLowerCase();
    return StartMethod.values.firstWhere(
      (method) => method.name == normalized,
      orElse: () => throw FormatException('Unsupported HTTP method: $value'),
    );
  }

  /// Upper-case wire representation.
  String get wire => name.toUpperCase();
}

/// Case-insensitive, multi-value HTTP headers.
final class StartHeaders {
  StartHeaders([Map<String, Iterable<String>> values = const {}]) {
    for (final entry in values.entries) {
      _values[entry.key.toLowerCase()] = List<String>.of(entry.value);
    }
  }

  factory StartHeaders.single(Map<String, String> values) => StartHeaders(
    values.map(
      (key, value) => MapEntry<String, Iterable<String>>(key, [value]),
    ),
  );

  final Map<String, List<String>> _values = <String, List<String>>{};

  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  List<String> values(String name) => List<String>.unmodifiable(
    _values[name.toLowerCase()] ?? const <String>[],
  );

  void set(String name, String value) {
    _values[name.toLowerCase()] = <String>[value];
  }

  void append(String name, String value) {
    _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add(value);
  }

  void remove(String name) => _values.remove(name.toLowerCase());

  void addAll(StartHeaders other) {
    for (final entry in other._values.entries) {
      _values[entry.key] = List<String>.of(entry.value);
    }
  }

  bool contains(String name) => _values.containsKey(name.toLowerCase());

  Map<String, List<String>> toMap() => Map<String, List<String>>.unmodifiable(
    _values.map(
      (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
    ),
  );

  StartHeaders copy() => StartHeaders(_values);
}

/// Platform-neutral incoming request.
final class StartRequest {
  StartRequest({
    required this.method,
    required this.uri,
    StartHeaders? headers,
    Stream<List<int>>? body,
    this.cancelled,
  }) : headers = headers ?? StartHeaders(),
       body = body ?? const Stream<List<int>>.empty();

  factory StartRequest.bytes({
    required StartMethod method,
    required Uri uri,
    StartHeaders? headers,
    List<int> body = const <int>[],
  }) => StartRequest(
    method: method,
    uri: uri,
    headers: headers,
    body: Stream<List<int>>.value(body),
  );

  final StartMethod method;
  final Uri uri;
  final StartHeaders headers;
  final Stream<List<int>> body;

  /// Completes when the adapter observes client disconnection.
  final Future<void>? cancelled;

  Future<Uint8List> readBytes({int maxBytes = 10 * 1024 * 1024}) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in body) {
      length += chunk.length;
      if (length > maxBytes) {
        throw StartPayloadTooLargeException(maxBytes);
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
final class StartResponse {
  StartResponse({
    this.status = 200,
    this.reason,
    StartHeaders? headers,
    Stream<List<int>>? body,
  }) : headers = headers ?? StartHeaders(),
       body = body ?? const Stream<List<int>>.empty();

  factory StartResponse.bytes(
    List<int> bytes, {
    int status = 200,
    String? contentType,
    StartHeaders? headers,
  }) {
    final resolved = headers?.copy() ?? StartHeaders();
    if (contentType != null) resolved.set('content-type', contentType);
    resolved.set('content-length', '${bytes.length}');
    return StartResponse(
      status: status,
      headers: resolved,
      body: Stream<List<int>>.value(bytes),
    );
  }

  factory StartResponse.text(
    String text, {
    int status = 200,
    String contentType = 'text/plain; charset=utf-8',
    StartHeaders? headers,
  }) => StartResponse.bytes(
    utf8.encode(text),
    status: status,
    contentType: contentType,
    headers: headers,
  );

  factory StartResponse.html(
    String html, {
    int status = 200,
    StartHeaders? headers,
  }) => StartResponse.text(
    html,
    status: status,
    contentType: 'text/html; charset=utf-8',
    headers: headers,
  );

  factory StartResponse.json(
    Object? value, {
    int status = 200,
    StartHeaders? headers,
  }) => StartResponse.bytes(
    utf8.encode(jsonEncode(value)),
    status: status,
    contentType: 'application/json; charset=utf-8',
    headers: headers,
  );

  factory StartResponse.redirect(Uri location, {int status = 302}) =>
      StartResponse(
        status: status,
        headers: StartHeaders.single(<String, String>{
          'location': location.toString(),
        }),
      );

  final int status;
  final String? reason;
  final StartHeaders headers;
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
final class StartPayloadTooLargeException implements Exception {
  const StartPayloadTooLargeException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Request body exceeds $maxBytes bytes.';
}
