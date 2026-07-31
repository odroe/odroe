import '../app/context.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'client.dart';
import 'http.dart';
import 'serializer.dart';

/// The application context key used to read the configured [RpcClient].
final rpcClientKey = ContextKey<RpcClient>('rpcClient');

/// Installs an RPC client into an application context.
final class RpcModule extends Module {
  /// Installs a caller-owned [client].
  RpcModule(this.client) : _transport = null;

  RpcModule._(this.client, this._transport);

  /// Creates an HTTP-backed client and owns its default transport.
  ///
  /// [headersProvider] runs once immediately before each request. Its result is
  /// copied before Odroe applies protocol-owned headers.
  /// [maxResponseFrameBytes] limits one typed value or stream frame, not the
  /// cumulative size of a streaming response.
  factory RpcModule.http({
    Uri? baseUri,
    HttpTransport? transport,
    Serializer? serializer,
    RpcHeadersProvider? headersProvider,
    String functionPath = '/__odroe/functions',
    int maxResponseFrameBytes = RpcClient.defaultMaxResponseFrameBytes,
  }) {
    if (maxResponseFrameBytes <= 0) {
      throw ArgumentError.value(
        maxResponseFrameBytes,
        'maxResponseFrameBytes',
        'Must be greater than zero.',
      );
    }
    final resolved = transport ?? HttpTransport();
    return RpcModule._(
      RpcClient(
        baseUri: baseUri ?? Uri.base,
        transport: resolved,
        serializer: serializer,
        headersProvider: headersProvider,
        functionPath: functionPath,
        maxResponseFrameBytes: maxResponseFrameBytes,
      ),
      transport == null ? resolved : null,
    );
  }

  /// The client registered by this module.
  final RpcClient client;

  final HttpTransport? _transport;

  @override
  void register(ModuleRegistry registry) {
    rpcClientKey.provide(registry, client);
  }

  @override
  void dispose(AppContext context) {
    _transport?.close();
  }
}
