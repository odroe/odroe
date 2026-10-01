import '../app/context.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'client.dart';
import 'http.dart';
import 'path.dart';
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
  /// [baseUri] must be an absolute HTTP(S) URI with a host and no user
  /// information. It may be omitted only for same-origin Web RPC, where
  /// [Uri.base] supplies the current browser location. Native applications
  /// must pass their server URI explicitly. Validation precedes client creation.
  ///
  /// [headersProvider] runs once immediately before each request. Its result is
  /// copied before Odroe applies protocol-owned headers.
  /// [maxRequestBodyBytes] configures the owned default [HttpTransport]. Pass
  /// a preconfigured [transport] instead when transport ownership stays with
  /// the caller; the two options are mutually exclusive.
  /// [maxResponseFrameBytes] limits one typed value or stream frame, not the
  /// cumulative size of a streaming response.
  factory RpcModule.http({
    Uri? baseUri,
    HttpTransport? transport,
    Serializer? serializer,
    RpcHeadersProvider? headersProvider,
    String functionPath = '/__odroe/functions',
    int? maxRequestBodyBytes,
    int maxResponseFrameBytes = RpcClient.defaultMaxResponseFrameBytes,
  }) {
    if (maxResponseFrameBytes <= 0) {
      throw ArgumentError.value(
        maxResponseFrameBytes,
        'maxResponseFrameBytes',
        'Must be greater than zero.',
      );
    }
    if (transport != null && maxRequestBodyBytes != null) {
      throw ArgumentError.value(
        maxRequestBodyBytes,
        'maxRequestBodyBytes',
        'Cannot configure the body budget of a caller-owned transport.',
      );
    }
    final resolvedBaseUri = baseUri ?? Uri.base;
    if (!_isValidHttpBaseUri(resolvedBaseUri)) {
      throw ArgumentError.value(
        resolvedBaseUri,
        'baseUri',
        'Must be an absolute HTTP(S) URI with a host and no user information. '
            'Omit only for same-origin Web RPC.',
      );
    }
    final resolvedFunctionPath = normalizeFunctionPath(
      functionPath,
      allowRelative: true,
    );
    final resolved =
        transport ??
        HttpTransport(
          maxRequestBodyBytes:
              maxRequestBodyBytes ?? HttpTransport.defaultMaxRequestBodyBytes,
        );
    return RpcModule._(
      RpcClient(
        baseUri: resolvedBaseUri,
        transport: resolved,
        serializer: serializer,
        headersProvider: headersProvider,
        functionPath: resolvedFunctionPath,
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

bool _isValidHttpBaseUri(Uri value) =>
    value.hasAuthority &&
    value.host.isNotEmpty &&
    (value.scheme == 'http' || value.scheme == 'https') &&
    value.userInfo.isEmpty;
