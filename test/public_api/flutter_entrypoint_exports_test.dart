import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart' as odroe;

void main() {
  test('Flutter composition exposes the application modules', () async {
    final modules = <odroe.Module>[
      odroe.QueryModule(),
      odroe.RpcModule.http(baseUri: Uri.parse('http://localhost')),
      odroe.DocumentModule(),
      odroe.RouterModule(routes: const <Never>[]),
    ];

    expect(modules, hasLength(4));
    expect(odroe.routerKey.name, 'router');
    final context = await odroe.AppContext.create(modules);
    await context.dispose();
  });
}
