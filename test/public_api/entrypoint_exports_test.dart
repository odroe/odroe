import 'package:odroe/database_postgres.dart' as postgres;
import 'package:odroe/rpc.dart' as rpc;
import 'package:test/test.dart';

void main() {
  test('product entrypoints expose dependency and control-flow types', () {
    const connectionSettings = postgres.ConnectionSettings();
    const poolSettings = postgres.PoolSettings(maxConnectionCount: 2);
    postgres.PostgresDatabase fromConnection(postgres.Connection connection) =>
        postgres.PostgresDatabase.fromConnection(connection);
    postgres.PostgresDatabase fromPool(postgres.Pool<void> pool) =>
        postgres.PostgresDatabase.fromPool(pool);
    rpc.HttpTransport transport(rpc.Client client) =>
        rpc.HttpTransport(client: client);
    const notFound = rpc.NotFound('missing');
    final redirect = rpc.Redirect(Uri.parse('/next'));

    expect(connectionSettings, isA<postgres.ConnectionSettings>());
    expect(poolSettings.maxConnectionCount, 2);
    expect(notFound.message, 'missing');
    expect(redirect.location.path, '/next');
    expect(<Object>[fromConnection, fromPool, transport], hasLength(3));
  });
}
