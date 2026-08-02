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
    await database.execute(
      BoundSql.raw('''
        CREATE TABLE posts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          author_id INTEGER REFERENCES users (id),
          title TEXT NOT NULL
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
        .one(database);
    expect(updated.nickname, 'Ada');

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

  test('checks zero, one, and multiple-row SELECT cardinality', () async {
    final read = queries.selectTable(
      users,
      orderBy: <SqlOrder>[users.id.ascending],
    );

    expect(await read.oneOrNull(database), isNull);
    await expectLater(read.one(database), throwsStateError);

    await queries
        .insert(users, <SqlAssignment>[users.email.set('only@example.com')])
        .execute(database);
    const only = (
      id: 1,
      email: 'only@example.com',
      nickname: null,
      active: true,
    );
    expect(await read.one(database), only);
    expect(await read.oneOrNull(database), only);

    await database.atomicWrite(<BoundSql>[
      queries.insert(users, <SqlAssignment>[
        users.email.set('second@example.com'),
      ]).statement,
      queries.insert(users, <SqlAssignment>[
        users.email.set('third@example.com'),
      ]).statement,
    ]);
    expect(await read.all(database), hasLength(3));
    await expectLater(read.one(database), throwsStateError);
    await expectLater(read.oneOrNull(database), throwsStateError);
  });

  test('supports nullable single-column projections', () async {
    await queries
        .insert(users, <SqlAssignment>[
          users.email.set('nullable@example.com'),
          users.nickname.set(null),
        ])
        .execute(database);

    final nullableNickname = queries.select(
      from: users,
      projection: SqlProjection.column(users.nickname),
      where: users.email.equals('nullable@example.com'),
    );
    expect(await nullableNickname.one(database), isNull);
    expect(await nullableNickname.oneOrNull(database), isNull);

    final missingNickname = queries.select(
      from: users,
      projection: SqlProjection.column(users.nickname),
      where: users.email.equals('missing@example.com'),
    );
    expect(await missingNickname.oneOrNull(database), isNull);
    await expectLater(missingNickname.one(database), throwsStateError);
  });

  test('can roll back a RETURNING cardinality failure', () async {
    await database.atomicWrite(<BoundSql>[
      queries.insert(users, <SqlAssignment>[
        users.email.set('first@example.com'),
      ]).statement,
      queries.insert(users, <SqlAssignment>[
        users.email.set('second@example.com'),
      ]).statement,
    ]);
    final setInactive = queries
        .updateAll(users, <SqlAssignment>[
          users.active.set(false),
        ], confirm: allRows)
        .returning(users.projection);

    await expectLater(setInactive.one(database), throwsStateError);
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

    await queries
        .updateAll(users, <SqlAssignment>[
          users.active.set(true),
        ], confirm: allRows)
        .execute(database);
    await expectLater(
      database.transaction<void>((transaction) async {
        await setInactive.one(transaction);
      }),
      throwsStateError,
    );
    expect(
      await queries
          .select(
            from: users,
            projection: SqlProjection.column(users.active),
            orderBy: <SqlOrder>[users.id.ascending],
          )
          .all(database),
      <bool>[true, true],
    );
  });

  test(
    'rejects typed SQL compiled for MySQL without changing SQLite',
    () async {
      const mysql = SqlQueries(SqlDialect.mysql);

      await expectLater(
        mysql
            .insert(users, <SqlAssignment>[
              users.email.set('wrong-dialect@example.com'),
            ])
            .execute(database),
        _throwsSql(SqlErrorCode.unsupported),
      );

      expect(await queries.selectTable(users).all(database), isEmpty);
    },
  );

  test('decodes an aliased RETURNING selection', () async {
    final returnedEmail = users.email.as('returned_email');

    expect(
      await queries
          .insert(users, <SqlAssignment>[users.email.set('alias@example.com')])
          .returning(SqlProjection.column(returnedEmail))
          .all(database),
      <String>['alias@example.com'],
    );
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

  test('executes typed INNER and LEFT JOIN projections', () async {
    final posts = _Posts();
    await queries
        .insert(users, <SqlAssignment>[
          users.email.set('ada@example.com'),
          users.active.set(true),
        ])
        .execute(database);
    await database.atomicWrite(<BoundSql>[
      queries.insert(posts, <SqlAssignment>[
        posts.authorId.set(1),
        posts.title.set('Typed relations'),
      ]).statement,
      queries.insert(posts, <SqlAssignment>[
        posts.authorId.set(null),
        posts.title.set('No author'),
      ]).statement,
    ]);

    final innerProjection = SqlProjection<({String title, String authorEmail})>(
      <SqlSelection<Object?>>[posts.title, users.email],
      (row) => (
        title: posts.title.read(row, 0),
        authorEmail: users.email.read(row, 1),
      ),
    );
    expect(
      await queries
          .select(
            from: posts,
            joins: <SqlJoin>[
              SqlJoin.inner(users, on: users.id.equalsColumn(posts.authorId)),
            ],
            projection: innerProjection,
          )
          .all(database),
      <({String title, String authorEmail})>[
        (title: 'Typed relations', authorEmail: 'ada@example.com'),
      ],
    );

    final optionalAuthor = users.email.optional.as('author_email');
    final leftProjection = SqlProjection<({String title, String? authorEmail})>(
      <SqlSelection<Object?>>[posts.title, optionalAuthor],
      (row) => (
        title: posts.title.read(row, 0),
        authorEmail: optionalAuthor.read(row, 1),
      ),
    );
    expect(
      await queries
          .select(
            from: posts,
            joins: <SqlJoin>[
              SqlJoin.left(users, on: posts.authorId.equalsColumn(users.id)),
            ],
            projection: leftProjection,
            orderBy: <SqlOrder>[posts.id.ascending],
          )
          .all(database),
      <({String title, String? authorEmail})>[
        (title: 'Typed relations', authorEmail: 'ada@example.com'),
        (title: 'No author', authorEmail: null),
      ],
    );
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

typedef _Post = ({int id, int? authorId, String title});

final class _Posts extends SqlTable<_Post> {
  _Posts() : super('posts');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<int?> authorId = column<int?>(
    'author_id',
    nullable(sqlInt),
  );
  late final SqlTableColumn<String> title = column<String>('title', sqlText);

  @override
  late final SqlProjection<_Post> projection = SqlProjection<_Post>(
    <SqlSelection<Object?>>[id, authorId, title],
    (row) => (
      id: id.read(row, 0),
      authorId: authorId.read(row, 1),
      title: title.read(row, 2),
    ),
  );
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}
