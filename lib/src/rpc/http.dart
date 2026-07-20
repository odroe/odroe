import 'package:http/http.dart' as http;

import '../server/http.dart';
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
    final outgoing = http.Request(request.method.wire, request.uri);
    for (final entry in request.headers.entries) {
      outgoing.headers[entry.key] = entry.value.join(', ');
    }
    outgoing.bodyBytes = await request.readBytes();
    final incoming = await _client.send(outgoing);
    return ServerResponse(
      status: incoming.statusCode,
      reason: incoming.reasonPhrase,
      headers: Headers.single(incoming.headers),
      body: incoming.stream,
    );
  }

  /// Closes the internally owned HTTP client, if any.
  void close() {
    if (_ownsClient) _client.close();
  }
}
