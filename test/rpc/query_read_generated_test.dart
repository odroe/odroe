import 'dart:convert';
import 'dart:io';

import 'package:odroe/src/router_compiler/compiler.dart';
import 'package:test/test.dart';

void main() {
  test(
    'unmodified compiler refs + generated record codecs + bridge + IoServer',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'odroe-query-rpc-generated-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String source) {
        final file = File('${root.path}/$path');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source);
      }

      write(
        'pubspec.yaml',
        'name: bridge_fixture\nenvironment:\n  sdk: ^3.10.0\n',
      );
      write(
        'lib/models.dart',
        'typedef Input = ({List<int> ids, Map<String, String> labels});',
      );
      write(
        'lib/routes/route.dart',
        "import 'package:odroe/router.dart';\nfinal route = AppRoute<NoParams, NoSearch, NoData>();",
      );
      write('lib/routes/server.dart', """
import 'package:odroe/server.dart';
import '../models.dart' as models;
import 'route.dart' as definition;
final route = definition.route.server();
final echo = ServerFunction<models.Input, models.Input>(id: 'generated.echo', handler: (context) => context.data);
""");
      final config =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map;
      final packages = config['packages'] as List;
      (packages.singleWhere((p) => p['name'] == 'odroe') as Map)['rootUri'] =
          Directory.current.uri.toString();
      packages.add({
        'name': 'bridge_fixture',
        'rootUri': root.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.10',
      });
      write('.dart_tool/package_config.json', jsonEncode(config));
      final output = FileRouteCompiler(projectRoot: root).compile();
      expect(output.diagnostics, isEmpty);
      write('lib/routes.dart', output.source);
      write('lib/routes.server.dart', output.serverSource);
      write('run.dart', """
import 'package:bridge_fixture/routes.dart' as client;
import 'package:bridge_fixture/routes.server.dart' as server;
import 'package:odroe/server_io.dart';
import 'package:odroe/query.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/query_rpc.dart';
Future<void> main() async {
  final runtime = server.createServer();
  final http = await IoServer.bind(runtime.handle, port: 0);
  final transport = HttpTransport(); final cache = QueryClient();
  try {
    final rpc = RpcClient(baseUri: Uri.parse('http://127.0.0.1:\${http.port}'), transport: transport);
    final ids = [1,2]; final labels = {'title':'original'};
    final options = client.routes.echo.read(rpc, (ids: ids, labels: labels), scope: ['tenant','alice']);
    ids.add(3); labels['title'] = 'changed';
    final output = await cache.fetchQuery(options);
    if (output.ids.join(',') != '1,2' || output.labels['title'] != 'original') {
      throw StateError('generated codec snapshot mismatch');
    }
    print('generated record ref / real HTTP / immutable input: passed');
  } finally { cache.clear(); transport.close(); await IoServer.close(http, force: true); await runtime.close(); }
}
""");
      final result = await Process.run(Platform.resolvedExecutable, [
        'run.dart',
      ], workingDirectory: root.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('immutable input: passed'));
      write('bad_api.dart', """
import 'package:odroe/query_rpc.dart';
void bad(RpcClient rpc) {
  const ref = ServerFunctionRef<int, int>(id: 'count');
  final QueryOptions<String> wrong = ref.read(rpc, 1, scope: ['tenant','alice']);
  PreparedRpcRead<int>? prepared;
  prepareRpcRead(rpc, ref, 1);
  rpcReadEndpoint(rpc, 'count');
  const stream = ServerStreamFunctionRef<int, int>(id: 'events');
  stream.read(rpc, 1, scope: ['tenant', 'alice']);
  print([wrong, prepared]);
}
""");
      final negative = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        'bad_api.dart',
      ], workingDirectory: root.path);
      expect(negative.exitCode, isNot(0));
      expect(negative.stdout, contains('invalid_assignment'));
      expect(negative.stdout, contains('undefined_class'));
      expect(negative.stdout, contains("'read' isn't defined"));
      expect(negative.stdout, contains("'prepareRpcRead' isn't defined"));
      expect(negative.stdout, contains("'rpcReadEndpoint' isn't defined"));
    },
  );
}
