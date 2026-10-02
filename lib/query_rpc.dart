/// Optional typed RPC reads backed by the existing Query runtime.
library;

import 'dart:convert';

import 'query.dart';
import 'src/rpc/client.dart';
import 'src/server/http.dart';

export 'query.dart';
export 'rpc.dart';

/// Explicitly declares a server function safe for Query retries and refetches.
///
/// The application owns [RpcClient] per account/backend and supplies a stable
/// cache scope. Its headers provider must never consult a global active account.
/// The scope contains identity, not credentials or mutation serialization scope.
extension RpcReadOptions<I, O> on ServerFunctionRef<I, O> {
  /// Snapshots this input with this ref's codec and the client's serializer.
  ///
  /// Returns native options. Rebuilding them updates future definitions without
  /// replacing same-key observers or in-flight work. Input is not re-encoded
  /// when sending. Credentials are obtained from the owning client at send time.
  /// Relative Web URLs follow the document base; native reads need an explicit
  /// HTTP(S) endpoint. Raw [ServerResponse] and streaming results are not values
  /// for this cache. Use direct RPC for those resources.
  ///
  /// Cancellation stops client work and excludes late results. Server-side
  /// cooperative cancellation depends on the transport observing disconnects.
  QueryOptions<O> read(
    RpcClient rpc,
    I input, {
    required List<String> scope,
    QueryPolicy policy = const QueryPolicy(),
  }) {
    final capturedScope = _scope(scope);
    final call = prepareRpcRead(rpc, this, input);
    return QueryOptions<O>(
      key: QueryKey<O>('rpc', [
        ..._prefix(call.endpoint, capturedScope),
        jsonDecode(call.payload),
      ]),
      policy: policy,
      query: (context) async {
        final value = await call(
          cancelled: context.cancelToken.whenCancelled.then<void>((_) {}),
        );
        if (value is ServerResponse) {
          try {
            await value.body.listen(null, onError: (Object _) {}).cancel();
          } on Object {
            // Cleanup must not replace the unsupported-value diagnostic.
          }
          throw UnsupportedError(_valueOnly);
        }
        if (value is Stream) throw UnsupportedError(_valueOnly);
        return value;
      },
    );
  }

  /// Selects this function's ordinary reads in one account/backend scope.
  QueryFilter reads(RpcClient rpc, {required List<String> scope}) {
    final capturedScope = _scope(scope);
    return QueryFilter(
      key: QueryKey<Object?>(
        'rpc',
        _prefix(rpcReadEndpoint(rpc, id), capturedScope),
      ),
    );
  }

  /// Selects one ordinary read by its canonical encoded input.
  QueryFilter readAt(RpcClient rpc, I input, {required List<String> scope}) =>
      QueryFilter(key: read(rpc, input, scope: scope).key, exact: true);

  List<String> _scope(List<String> scope) {
    // Null itself is a reusable value, even though it is a subtype of both
    // nullable resource types.
    if (this is! ServerFunctionRef<I, Null> &&
        (this is ServerFunctionRef<I, ServerResponse?> ||
            this is ServerFunctionRef<I, Stream?>)) {
      throw UnsupportedError(_valueOnly);
    }
    if (scope.isEmpty || scope.any((part) => part.isEmpty)) {
      throw ArgumentError(
        'An explicit account/tenant cache scope is required.',
      );
    }
    return List<String>.unmodifiable(scope);
  }

  List<Object?> _prefix(Uri endpoint, List<String> scope) {
    return [endpoint.toString(), scope, id, method.name, 'query'];
  }
}

const _valueOnly =
    'RPC Query reads require reusable values, not ServerResponse or Stream. '
    'Use RpcClient.call or RpcClient.stream directly for response resources.';
