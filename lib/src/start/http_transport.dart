import 'package:http/http.dart' as http;

import 'request.dart';
import 'server_function.dart';

/// Cross-platform HTTP transport backed by package:http.
final class HttpStartTransport implements StartTransport {
  HttpStartTransport({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<StartResponse> send(StartRequest request) async {
    final outgoing = http.Request(request.method.wire, request.uri);
    for (final entry in request.headers.toMap().entries) {
      outgoing.headers[entry.key] = entry.value.join(', ');
    }
    outgoing.bodyBytes = await request.readBytes();
    final incoming = await _client.send(outgoing);
    return StartResponse(
      status: incoming.statusCode,
      reason: incoming.reasonPhrase,
      headers: StartHeaders.single(incoming.headers),
      body: incoming.stream,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
