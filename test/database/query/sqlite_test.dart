import 'package:odroe/database_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late SqliteDatabase database;
  late _Users users;
  const queries = SqlQueries(SqlDialect.sqlite);

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    users = _Users();
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          nickname TEXT,
          active INTEGER NOT NULL DEFAULT 1
        ) STRICT
      '''),
    );
  });

  tearDown(() => database.close());

  test('runs typed SQLite CRUD and RETURNING', () async {
    final inserted = await queries
        .insert(users, <SqlAssignment>[
          users.email.set('ada@example.com'),
          users.nickname.set(null),
          users.active.set(true),
        ])
        .execute(database);
    expect(inserted.affectedRows, 1);
    expect(inserted.lastInsertId, 1);

    final grace = await queries
        .insert(users, <SqlAssignment>[
          users.email.set('grace@example.com'),
          users.nickname.set('Grace'),
        ])
        .returning(users.projection)
        .all(database);
    expect(grace, <_User>[
      (id: 2, email: 'grace@example.com', nickname: 'Grace', active: true),
    ]);

    final selected = await queries
        .selectTable(
          users,
          where: users.active.equals(true).and(users.nickname.isNotNull),
          orderBy: <SqlOrder>[users.id.descending],
          limit: 1,
        )
        .all(database);
    expect(selected, grace);

    final updated = await queries
        .updateWhere(users, <SqlAssignment>[
          users.nickname.set('Ada'),
        ], where: users.email.equals('ada@example.com'))
        .returning(users.projection)
        .all(database);
    expect(updated.single.nickname, 'Ada');

    final deleted = await queries
        .deleteWhere(users, where: users.email.equals('grace@example.com'))
        .returning(SqlProjection.column(users.email))
        .all(database);
    expect(deleted, <String>['grace@example.com']);

    final remaining = await queries.selectTable(users).all(database);
    expect(remaining, <_User>[
      (id: 1, email: 'ada@example.com', nickname: 'Ada', active: true),
    ]);
  });

  test('uses the callback executor and rolls back typed writes', () async {
    await expectLater(
      database.transaction<void>((transaction) async {
        await queries
            .insert(users, <SqlAssignment>[
              users.email.set('temporary@example.com'),
            ])
            .execute(transaction);
        expect(await queries.selectTable(users).all(transaction), hasLength(1));
        throw StateError('abort');
      }),
      throwsStateError,
    );

    expect(await queries.selectTable(users).all(database), isEmpty);
  });

  test('executes explicit full-table mutations', () async {
    await database.atomicWrite(<BoundSql>[
      queries.insert(users, <SqlAssignment>[
        users.email.set('first@example.com'),
      ]).statement,
      queries.insert(users, <SqlAssignment>[
        users.email.set('second@example.com'),
      ]).statement,
    ]);

    final updated = await queries
        .updateAll(users, <SqlAssignment>[
          users.active.set(false),
        ], confirm: allRows)
        .execute(database);
    expect(updated.affectedRows, 2);
    expect(
      await queries
          .select(
            from: users,
            projection: SqlProjection.column(users.active),
            orderBy: <SqlOrder>[users.id.ascending],
          )
          .all(database),
      <bool>[false, false],
    );

    final deleted = await queries
        .deleteAll(users, confirm: allRows)
        .execute(database);
    expect(deleted.affectedRows, 2);
    expect(await queries.selectTable(users).all(database), isEmpty);
  });
}

typedef _User = ({int id, String email, String? nickname, bool active});

final class _Users extends SqlTable<_User> {
  _Users() : super('users');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<String> email = column<String>('email', sqlText);
  late final SqlTableColumn<String?> nickname = column<String?>(
    'nickname',
    nullable(sqlText),
  );
  late final SqlTableColumn<bool> active = column<bool>('active', sqlBool);

  @override
  late final SqlProjection<_User> projection = SqlProjection<_User>(
    <SqlTableColumn<Object?>>[id, email, nickname, active],
    (row) => (
      id: id.read(row, 0),
      email: email.read(row, 1),
      nickname: nickname.read(row, 2),
      active: active.read(row, 3),
    ),
  );
}
