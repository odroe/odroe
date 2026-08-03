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

  test(
    'updates numeric columns atomically without a read-modify-write',
    () async {
      await database.execute(
        BoundSql.raw('''
        CREATE TABLE counters (
          id INTEGER PRIMARY KEY,
          value INTEGER NOT NULL,
          ratio REAL NOT NULL
        ) STRICT
      '''),
      );
      final counters = _Counters();
      await queries
          .insertMany(counters, <List<SqlAssignment>>[
            <SqlAssignment>[
              counters.id.set(1),
              counters.value.set(10),
              counters.ratio.set(1.5),
            ],
            <SqlAssignment>[
              counters.id.set(2),
              counters.value.set(7),
              counters.ratio.set(2.0),
            ],
          ])
          .execute(database);

      final updated = await queries
          .updateWhere(counters, <SqlUpdateAssignment>[
            counters.value.incrementBy(5),
            counters.ratio.incrementBy(0.25),
          ], where: counters.id.equals(1))
          .returning(counters.projection)
          .one(database);
      expect(updated, (id: 1, value: 15, ratio: 1.75));

      final decremented = await queries
          .updateWhere(counters, <SqlUpdateAssignment>[
            counters.value.incrementBy(-3),
          ], where: counters.id.equals(1))
          .execute(database);
      expect(decremented.affectedRows, 1);

      final guarded = await queries
          .updateWhere(
            counters,
            <SqlUpdateAssignment>[counters.value.incrementBy(-13)],
            where: counters.id
                .equals(1)
                .and(counters.value.greaterThanOrEqual(13)),
          )
          .execute(database);
      expect(guarded.affectedRows, 0);

      final all = await queries
          .updateAll(counters, <SqlUpdateAssignment>[
            counters.value.incrementBy(-1),
          ], confirm: allRows)
          .execute(database);
      expect(all.affectedRows, 2);
      expect(
        await queries
            .selectTable(counters, orderBy: <SqlOrder>[counters.id.ascending])
            .all(database),
        <({int id, int value, double ratio})>[
          (id: 1, value: 11, ratio: 1.75),
          (id: 2, value: 6, ratio: 2.0),
        ],
      );
    },
  );

  test('runs atomic multi-row INSERT with typed RETURNING', () async {
    final inserted = await queries
        .insertMany(users, <List<SqlAssignment>>[
          <SqlAssignment>[
            users.email.set('ada@example.com'),
            users.nickname.set('Ada'),
            users.active.set(true),
          ],
          <SqlAssignment>[
            users.email.set('grace@example.com'),
            users.nickname.set(null),
            users.active.set(false),
          ],
        ])
        .returning(users.projection)
        .all(database);
    // SQL RETURNING does not guarantee input order; email is the stable key.
    final insertedByEmail = <String, _User>{
      for (final user in inserted) user.email: user,
    };
    expect(
      insertedByEmail.keys,
      unorderedEquals(<String>['ada@example.com', 'grace@example.com']),
    );
    expect(inserted.map((user) => user.id), unorderedEquals(<int>[1, 2]));
    expect(insertedByEmail['ada@example.com']?.nickname, 'Ada');
    expect(insertedByEmail['ada@example.com']?.active, isTrue);
    expect(insertedByEmail['grace@example.com']?.nickname, isNull);
    expect(insertedByEmail['grace@example.com']?.active, isFalse);

    await expectLater(
      queries
          .insertMany(users, <List<SqlAssignment>>[
            <SqlAssignment>[
              users.email.set('temporary@example.com'),
              users.active.set(true),
            ],
            <SqlAssignment>[
              users.email.set('ada@example.com'),
              users.active.set(false),
            ],
          ])
          .execute(database),
      _throwsSql(SqlErrorCode.constraint),
    );
    final remaining = await queries.selectTable(users).all(database);
    expect(<String, _User>{
      for (final user in remaining) user.email: user,
    }, insertedByEmail);
  });

  test('executes typed membership predicates for reads and writes', () async {
    await queries
        .insertMany(users, <List<SqlAssignment>>[
          <SqlAssignment>[
            users.email.set('ada@example.com'),
            users.nickname.set('Ada'),
          ],
          <SqlAssignment>[
            users.email.set('grace@example.com'),
            users.nickname.set(null),
          ],
          <SqlAssignment>[
            users.email.set('linus@example.com'),
            users.nickname.set('Linus'),
          ],
        ])
        .execute(database);

    expect(
      await queries
          .selectTable(
            users,
            where: users.id.isIn(<int>[3, 1]),
            orderBy: <SqlOrder>[users.id.ascending],
          )
          .all(database),
      <_User>[
        (id: 1, email: 'ada@example.com', nickname: 'Ada', active: true),
        (id: 3, email: 'linus@example.com', nickname: 'Linus', active: true),
      ],
    );
    expect(
      await queries
          .selectTable(
            users,
            where: users.nickname.isIn(<String?>['Ada', null]),
            orderBy: <SqlOrder>[users.id.ascending],
          )
          .all(database),
      <_User>[
        (id: 1, email: 'ada@example.com', nickname: 'Ada', active: true),
        (id: 2, email: 'grace@example.com', nickname: null, active: true),
      ],
    );
    expect(
      await queries
          .selectTable(users, where: users.nickname.isNotIn(<String?>['Ada']))
          .all(database),
      <_User>[
        (id: 3, email: 'linus@example.com', nickname: 'Linus', active: true),
      ],
    );
    expect(
      await queries
          .selectTable(
            users,
            where: users.nickname.isNotIn(<String?>['Ada', null]),
          )
          .all(database),
      <_User>[
        (id: 3, email: 'linus@example.com', nickname: 'Linus', active: true),
      ],
    );
    expect(
      await queries
          .selectTable(users, where: users.id.isIn(const <int>[]))
          .all(database),
      isEmpty,
    );
    expect(
      () => queries.updateWhere(users, <SqlAssignment>[
        users.active.set(false),
      ], where: users.id.isNotIn(const <int>[])),
      throwsArgumentError,
    );
    expect(
      () => queries.deleteWhere(users, where: users.id.isNotIn(const <int>[])),
      throwsArgumentError,
    );

    final updated = await queries
        .updateWhere(users, <SqlAssignment>[
          users.active.set(false),
        ], where: users.id.isIn(<int>[1, 3]))
        .execute(database);
    expect(updated.affectedRows, 2);

    final deleted = await queries
        .deleteWhere(users, where: users.id.isNotIn(<int>[1, 3]))
        .execute(database);
    expect(deleted.affectedRows, 1);
    expect(
      await queries
          .select(
            from: users,
            projection: SqlProjection.column(users.id),
            orderBy: <SqlOrder>[users.id.ascending],
          )
          .all(database),
      <int>[1, 3],
    );
  });

  test('inserts once for a targeted conflict and preserves the row', () async {
    final first = await queries
        .insertOnConflictDoNothing(
          users,
          <SqlAssignment>[
            users.email.set('stable@example.com'),
            users.nickname.set('Original'),
            users.active.set(true),
          ],
          target: <SqlTableColumn<Object?>>[users.email],
        )
        .execute(database);
    expect(first.affectedRows, 1);

    final duplicate = await queries
        .insertOnConflictDoNothing(
          users,
          <SqlAssignment>[
            users.email.set('stable@example.com'),
            users.nickname.set('Replacement'),
            users.active.set(false),
          ],
          target: <SqlTableColumn<Object?>>[users.email],
        )
        .execute(database);
    expect(duplicate.affectedRows, 0);

    final returned = await queries
        .insertOnConflictDoNothing(
          users,
          <SqlAssignment>[
            users.email.set('stable@example.com'),
            users.nickname.set('Returned replacement'),
            users.active.set(false),
          ],
          target: <SqlTableColumn<Object?>>[users.email],
        )
        .returning(users.projection)
        .all(database);
    expect(returned, isEmpty);

    expect(
      await queries
          .selectTable(users, where: users.email.equals('stable@example.com'))
          .one(database),
      (id: 1, email: 'stable@example.com', nickname: 'Original', active: true),
    );
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

final class _Counters extends SqlTable<({int id, int value, double ratio})> {
  _Counters() : super('counters');

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<int> value = column<int>('value', sqlInt);
  late final SqlTableColumn<double> ratio = column<double>('ratio', sqlDouble);

  @override
  late final SqlProjection<({int id, int value, double ratio})> projection =
      SqlProjection<({int id, int value, double ratio})>(
        <SqlSelection<Object?>>[id, value, ratio],
        (row) => (
          id: id.read(row, 0),
          value: value.read(row, 1),
          ratio: ratio.read(row, 2),
        ),
      );
}

Matcher _throwsSql(SqlErrorCode code) {
  return throwsA(
    isA<SqlException>().having((error) => error.code, 'code', code),
  );
}
