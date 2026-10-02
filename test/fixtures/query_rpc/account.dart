import 'package:odroe/rpc.dart';

// Application auth state, not an Odroe session/runtime. Identity and endpoint
// stay fixed; only this account's credential may refresh. Cookies are not covered.
final class Account {
  Account({
    required this.tenant,
    required this.id,
    required Uri baseUri,
    required RpcTransport transport,
    required this.token,
    String functionPath = 'rpc',
    Serializer? serializer,
  }) {
    rpc = RpcClient(
      baseUri: baseUri,
      functionPath: functionPath,
      transport: transport,
      serializer: serializer,
      headersProvider: () => Headers.single({
        'x-tenant': tenant,
        'x-account': id,
        'authorization': 'Bearer $token',
      }),
    );
  }
  final String tenant;
  final String id;
  late final RpcClient rpc;
  String token;
  int _refreshGeneration = 0;
  List<String> get scope => [tenant, id];
}

// An async refresh may finish after a switch, or after a newer refresh.
// Neither may replace the credentials belonging to the currently selected owner.
Future<bool> refreshAccountToken(
  Account Function() current,
  Future<String> Function(Account owner) fetchToken,
) async {
  final owner = current();
  final generation = ++owner._refreshGeneration;
  final token = await fetchToken(owner);
  if (!identical(current(), owner) || generation != owner._refreshGeneration) {
    return false;
  }
  owner.token = token;
  return true;
}
