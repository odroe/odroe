import '../app/context.dart';
import '../app/key.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'client.dart';
import 'http.dart';
import 'serializer.dart';

/// The application context key used to read the configured [RpcClient].
const rpcClientKey = ContextKey<RpcClient>('rpcClient');

/// Installs an RPC client into an application context.
final class RpcModule extends Module {
  /// Installs a caller-owned [client].
  RpcModule(this.client) : _transport = null;

  RpcModule._(this.client, this._transport);

  /// Creates an HTTP-backed client and owns its default transport.
  ///
  /// [baseUri] must be an absolute HTTP(S) URI with a host and no user
  /// information. Omit it only for same-origin Web RPC, where [Uri.base]
  /// supplies the browser location. Native applications must pass their
  /// server URI explicitly. Validation happens before creating a transport.
  factory RpcModule.http({
    Uri? baseUri,
    HttpTransport? transport,
    Serializer? serializer,
    String functionPath = '/__odroe/functions',
  }) {
    final resolvedBaseUri = baseUri ?? Uri.base;
    if (!resolvedBaseUri.hasAuthority ||
        resolvedBaseUri.host.isEmpty ||
        (resolvedBaseUri.scheme != 'http' &&
            resolvedBaseUri.scheme != 'https') ||
        resolvedBaseUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        resolvedBaseUri,
        'baseUri',
        'Must be an absolute HTTP(S) URI with a host and no user information. '
            'Omit only for same-origin Web RPC.',
      );
    }
    final resolved = transport ?? HttpTransport();
    return RpcModule._(
      RpcClient(
        baseUri: resolvedBaseUri,
        transport: resolved,
        serializer: serializer,
        functionPath: functionPath,
      ),
      transport == null ? resolved : null,
    );
  }

  /// The client registered by this module.
  final RpcClient client;

  final HttpTransport? _transport;

  @override
  void register(ModuleRegistry registry) {
    registry.provide(rpcClientKey, client);
  }

  @override
  void dispose(AppContext context) {
    _transport?.close();
  }
}
