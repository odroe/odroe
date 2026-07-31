import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../server/http.dart';
import 'cancellation.dart';
import 'client.dart';

/// Cross-platform HTTP transport backed by package:http.
final class HttpTransport implements RpcTransport {
  /// Creates a transport, optionally reusing an existing HTTP [client].
  HttpTransport({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    var callerCancelled = false;
    final abortTrigger = request.cancelled?.then<void>(
      (_) => callerCancelled = true,
      onError: (Object _, StackTrace _) => callerCancelled = true,
    );
    final outgoing = http.AbortableRequest(
      request.method.wire,
      request.uri,
      abortTrigger: abortTrigger,
    );
    for (final entry in request.headers.entries) {
      outgoing.headers[entry.key] = entry.value.join(', ');
    }
    outgoing.bodyBytes = await runUntilRpcCancelled(
      () => _readBytes(stopOnRpcCancellation(request.body, request.cancelled)),
      request.cancelled,
    );

    Future<http.StreamedResponse>? pending;
    late final http.StreamedResponse incoming;
    try {
      incoming = await runUntilRpcCancelled(
        () => pending = _client.send(outgoing),
        request.cancelled,
      );
    } on http.RequestAbortedException catch (_, stackTrace) {
      if (callerCancelled) {
        Error.throwWithStackTrace(const RpcCancelledException(), stackTrace);
      }
      rethrow;
    } on RpcCancelledException {
      final lateResponse = pending;
      if (lateResponse != null) {
        unawaited(
          lateResponse.then<void>(
            (response) => _cancelBody(response.stream),
            onError: (Object _, StackTrace _) {},
          ),
        );
      }
      rethrow;
    }
    return ServerResponse(
      status: incoming.statusCode,
      reason: incoming.reasonPhrase,
      headers: Headers.single(incoming.headers),
      body: incoming.stream.handleError((Object error, StackTrace stackTrace) {
        if (callerCancelled) {
          Error.throwWithStackTrace(const RpcCancelledException(), stackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }, test: (error) => error is http.RequestAbortedException),
    );
  }

  /// Closes the internally owned HTTP client, if any.
  void close() {
    if (_ownsClient) _client.close();
  }
}

Future<Uint8List> _readBytes(Stream<List<int>> body) async {
  const maxBytes = 10 * 1024 * 1024;
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in body) {
    length += chunk.length;
    if (length > maxBytes) throw const PayloadTooLargeException(maxBytes);
    builder.add(chunk);
  }
  return builder.takeBytes();
}

void _cancelBody(Stream<List<int>> body) {
  final subscription = body.listen(
    null,
    onError: (Object _) {
      // Cancellation already won the request.
    },
  );
  unawaited(
    subscription.cancel().then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    ),
  );
}
