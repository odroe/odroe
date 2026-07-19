// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import '../server/context.dart';
import '../server/http.dart';
import 'function.dart';
import 'serializer.dart';

final class ServerFunctionRef<I, O> {
  const ServerFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.decodeOutput,
  });

  final String id;
  final HttpMethod method;
  final ValueDecoder<O>? decodeOutput;

  Future<O> call(RpcClient client, I data) => client.call(this, data);
}

final class ServerStreamFunctionRef<I, T> {
  const ServerStreamFunctionRef({
    required this.id,
    this.method = HttpMethod.post,
    this.decodeOutput,
  });

  final String id;
  final HttpMethod method;
  final ValueDecoder<T>? decodeOutput;

  Future<Stream<T>> call(RpcClient client, I data) => client.stream(this, data);
}

abstract interface class RpcTransport {
  Future<ServerResponse> send(ServerRequest request);
}

/// Typed client for generated server-function references.
final class RpcClient {
  RpcClient({
    required this.baseUri,
    required this.transport,
    Serializer? serializer,
    this.functionPath = '/__odroe/functions',
  }) : serializer = serializer ?? Serializer();

  final Uri baseUri;
  final RpcTransport transport;
  final Serializer serializer;
  final String functionPath;

  Future<O> call<I, O>(ServerFunctionRef<I, O> function, I data) async {
    final response = await _send(function.id, function.method, data);
    if (O == ServerResponse) return response as O;
    final contentType = response.headers.value('content-type') ?? '';
    if (contentType.startsWith('application/x-ndjson')) {
      throw const RpcProtocolException(
        'The server returned a stream for a value function.',
      );
    }
    return _decodeFrame<O>(
      await _readFrame(response),
      response.status,
      decode: function.decodeOutput,
    );
  }

  Future<Stream<T>> stream<I, T>(
    ServerStreamFunctionRef<I, T> function,
    I data,
  ) async {
    final response = await _send(function.id, function.method, data);
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.startsWith('application/x-ndjson')) {
      _decodeFrame<Object?>(await _readFrame(response), response.status);
      throw const RpcProtocolException(
        'The server returned one value for a streaming function.',
      );
    }
    return response.body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.isNotEmpty)
        .map<dynamic>((line) {
          final frame = Map<String, Object?>.from(jsonDecode(line) as Map);
          if (frame['type'] == 'error') {
            throw RemoteServerException(
              frame['message'] as String? ?? 'Server stream failed.',
              status: response.status,
            );
          }
          final value = serializer.decode(frame['data']);
          return function.decodeOutput?.call(value) ?? value;
        })
        .cast<T>();
  }

  Future<ServerResponse> _send<I>(String id, HttpMethod method, I data) {
    final payload = serializer.encodeJson(<String, Object?>{
      'data': data is NoServerInput ? null : data,
    });
    final path = '$functionPath/${Uri.encodeComponent(id)}';
    if (method == HttpMethod.get) {
      return transport.send(
        ServerRequest.bytes(
          method: method,
          uri: baseUri
              .resolve(path)
              .replace(queryParameters: <String, String>{'payload': payload}),
          headers: _rpcHeaders(baseUri),
        ),
      );
    }
    return transport.send(
      ServerRequest.bytes(
        method: method,
        uri: baseUri.resolve(path),
        headers: _rpcHeaders(baseUri)
          ..set('content-type', 'application/json; charset=utf-8'),
        body: utf8.encode(payload),
      ),
    );
  }

  Future<Map<String, Object?>> _readFrame(ServerResponse response) async {
    final text = await response.readText();
    return text.isEmpty
        ? <String, Object?>{'type': 'data', 'data': null}
        : Map<String, Object?>.from(jsonDecode(text) as Map);
  }

  O _decodeFrame<O>(
    Map<String, Object?> frame,
    int status, {
    ValueDecoder<O>? decode,
  }) {
    switch (frame['type']) {
      case 'data':
        final value = serializer.decode(frame['data']);
        return decode?.call(value) ?? value as O;
      case 'redirect':
        throw Redirect(
          Uri.parse(frame['location']! as String),
          status: frame['status']! as int,
        );
      case 'notFound':
        throw NotFound(frame['message'] as String? ?? 'Not found');
      default:
        throw RemoteServerException(
          frame['message'] as String? ?? 'Server function failed.',
          status: status,
          remoteType: frame['errorType'] as String?,
        );
    }
  }
}

final class RpcProtocolException implements Exception {
  const RpcProtocolException(this.message);

  final String message;

  @override
  String toString() => 'RpcProtocolException: $message';
}

Headers _rpcHeaders(Uri baseUri) => Headers.single(<String, String>{
  'accept': 'application/json, application/x-ndjson',
  'x-odroe-server-function': 'true',
  'origin': _origin(baseUri),
});

String _origin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

final class RemoteServerException implements Exception {
  const RemoteServerException(
    this.message, {
    required this.status,
    this.remoteType,
  });

  final String message;
  final int status;
  final String? remoteType;

  @override
  String toString() => remoteType == null
      ? 'RemoteServerException($status): $message'
      : 'RemoteServerException($status, $remoteType): $message';
}
