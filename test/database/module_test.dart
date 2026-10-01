import 'package:odroe/database_sqlite.dart';
import 'package:odroe/odroe.dart';
import 'package:test/test.dart';

void main() {
  test('borrowed database outlives its application context', () async {
    final database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    final context = await AppContext.create(<Module>[
      DatabaseModule.borrowed(database),
    ]);

    expect(context.read(databaseKey), same(database));
    await context.dispose();

    final values = await database.query(
      BoundSql.raw('SELECT 1'),
      (row) => row.read(0, sqlInt),
    );
    expect(values, <int>[1]);
  });

  test('owned database closes with its application context', () async {
    final database = SqliteDatabase.openInMemory();
    final context = await AppContext.create(<Module>[
      DatabaseModule.owned(database),
    ]);

    await context.dispose();

    await expectLater(
      database.query(BoundSql.raw('SELECT 1'), (row) => row),
      throwsA(
        isA<SqlException>().having(
          (error) => error.code,
          'code',
          SqlErrorCode.closed,
        ),
      ),
    );
  });
}
