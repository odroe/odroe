import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:odroe/database_sqlite.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'server close drains borrowed SQLite before closing the process owner',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'odroe-server-lifecycle-',
      );
      final path = '${temporary.path}/app.sqlite';
      final database = SqliteDatabase.open(path);
      final bodyStarted = Completer<void>();
      final bodyGate = Completer<void>();
      final events = <String>[];
      var moduleCalls = 0;
      var requestDisposeCalls = 0;
      var closeCalls = 0;
      Future<String>? body;
      late final Server server;

      addTearDown(() async {
        if (!bodyGate.isCompleted) bodyGate.complete();
        try {
          await body;
        } on Object {
          // Preserve the test failure while still releasing the database file.
        }
        try {
          await server.close();
        } on Object {
          // The lifecycle assertions report any close failure.
        }
        await database.close();
        if (temporary.existsSync()) await temporary.delete(recursive: true);
      });

      await database.execute(
        BoundSql.raw(
          'CREATE TABLE records (id INTEGER PRIMARY KEY, value INTEGER)',
        ),
      );
      await database.execute(BoundSql.raw('INSERT INTO records VALUES (1, 7)'));

      server = Server(
        routes: const [],
        modules: () {
          moduleCalls++;
          return <Module>[
            DatabaseModule.borrowed(database),
            _RequestDisposeProbe(
              events,
              onDispose: () => requestDisposeCalls++,
            ),
          ];
        },
        middleware: [
          (context, _) async {
            final value = await _readValue(context.read(databaseKey));

            Stream<List<int>> responseBody() async* {
              bodyStarted.complete();
              yield utf8.encode('$value');
              await bodyGate.future;
            }

            return ServerResponse(body: responseBody());
          },
        ],
        onClose: () async {
          closeCalls++;
          events.add('owner:close');
          await database.close();
        },
      );

      final response = await server.handle(_request());
      body = response.readText();
      await bodyStarted.future;

      final firstClose = server.close();
      final secondClose = server.close();
      expect(secondClose, same(firstClose));
      expect(closeCalls, 0);
      expect(requestDisposeCalls, 0);
      expect(await _readValue(database), 7);
      await expectLater(server.handle(_request()), throwsStateError);

      bodyGate.complete();
      expect(await body, '7');
      await firstClose;

      expect(moduleCalls, 1);
      expect(requestDisposeCalls, 1);
      expect(closeCalls, 1);
      expect(events, <String>['request:dispose', 'owner:close']);
      expect(server.close(), same(firstClose));

      await expectLater(
        _readValue(database),
        throwsA(
          isA<SqlException>().having(
            (error) => error.code,
            'code',
            SqlErrorCode.closed,
          ),
        ),
      );

      final reopened = SqliteDatabase.open(path);
      try {
        expect(await _readValue(reopened), 7);
      } finally {
        await reopened.close();
      }
    },
  );
}

final class _RequestDisposeProbe extends Module {
  _RequestDisposeProbe(this.events, {required this.onDispose});

  final List<String> events;
  final void Function() onDispose;

  @override
  void register(ModuleRegistry registry) {}

  @override
  Future<void> dispose(AppContext context) async {
    expect(await _readValue(context.read(databaseKey)), 7);
    onDispose();
    events.add('request:dispose');
  }
}

Future<int> _readValue(SqlDatabase database) async {
  final values = await database.query(
    BoundSql.raw('SELECT value FROM records WHERE id = 1'),
    (row) => row.read(0, sqlInt),
  );
  return values.single;
}

ServerRequest _request() => ServerRequest.bytes(
  method: HttpMethod.get,
  uri: Uri.parse('http://localhost/'),
);
