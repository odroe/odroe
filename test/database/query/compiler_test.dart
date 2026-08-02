import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  group('dialects', () {
    for (final dialect in SqlDialect.values) {
      test('${dialect.name} compiles bound INSERT and SELECT statements', () {
        final users = _Users();
        final queries = SqlQueries(dialect);
        final quote = dialect == SqlDialect.mysql ? '`' : '"';

        final insert = queries.insert(users, <SqlAssignment>[
          users.email.set('ada@example.com'),
          users.active.set(true),
        ]);
        expect(insert.statement.fragments, <String>[
          'INSERT INTO ${quote}users$quote '
              '(${quote}email$quote, ${quote}active$quote) VALUES (',
          ', ',
          ')',
        ]);
        expect(_values(insert.statement), <Object?>['ada@example.com', true]);
        expect(insert.statement.kind, SqlStatementKind.write);
        expect(insert.statement.dialect, dialect);

        final select = queries.selectTable(
          users,
          where: users.id.greaterThan(10).and(users.nickname.equals(null)),
          orderBy: <SqlOrder>[users.email.descending],
          limit: 5,
          offset: 2,
        );
        expect(select.statement.fragments, <String>[
          'SELECT ${quote}id$quote, ${quote}email$quote, '
              '${quote}nickname$quote, ${quote}active$quote '
              'FROM ${quote}users$quote WHERE (${quote}id$quote > ',
          ' AND ${quote}nickname$quote IS NULL) '
              'ORDER BY ${quote}email$quote DESC LIMIT 5 OFFSET 2',
        ]);
        expect(_values(select.statement), <Object?>[10]);
        expect(select.statement.kind, SqlStatementKind.rowReturning);
        expect(select.statement.dialect, dialect);
      });
    }

    test('quotes schema, table, and column as separate identifiers', () {
      final sqliteTable = _NamedTable(
        'user.logs',
        schema: 'tenant"one',
        columnName: 'select"value',
      );
      final mysqlTable = _NamedTable(
        'user.logs',
        schema: 'tenant`one',
        columnName: 'select`value',
      );

      expect(
        const SqlQueries(
          SqlDialect.postgres,
        ).selectTable(sqliteTable).statement.fragments.single,
        'SELECT "select""value" FROM "tenant""one"."user.logs"',
      );
      expect(
        const SqlQueries(
          SqlDialect.mysql,
        ).selectTable(mysqlTable).statement.fragments.single,
        'SELECT `select``value` FROM `tenant``one`.`user.logs`',
      );
    });

    test('uses dialect-specific empty INSERT syntax', () {
      final users = _Users();

      expect(
        const SqlQueries(
          SqlDialect.sqlite,
        ).insert(users, const <SqlAssignment>[]).statement.fragments.single,
        'INSERT INTO "users" DEFAULT VALUES',
      );
      expect(
        const SqlQueries(
          SqlDialect.postgres,
        ).insert(users, const <SqlAssignment>[]).statement.fragments.single,
        'INSERT INTO "users" DEFAULT VALUES',
      );
      expect(
        const SqlQueries(
          SqlDialect.mysql,
        ).insert(users, const <SqlAssignment>[]).statement.fragments.single,
        'INSERT INTO `users` () VALUES ()',
      );
    });

    test('rejects MySQL RETURNING before execution', () {
      final users = _Users();
      final write = const SqlQueries(
        SqlDialect.mysql,
      ).insert(users, <SqlAssignment>[users.email.set('ada@example.com')]);

      expect(
        () => write.returning(users.projection),
        _throwsSql(SqlErrorCode.unsupported),
      );
    });

    for (final dialect in <SqlDialect>[
      SqlDialect.sqlite,
      SqlDialect.postgres,
    ]) {
      test('${dialect.name} compiles targeted conflict inserts', () {
        final users = _Users();
        final queries = SqlQueries(dialect);
        final insert = queries.insertOnConflictDoNothing(
          users,
          <SqlAssignment>[
            users.email.set('ada@example.com'),
            users.active.set(true),
          ],
          target: <SqlTableColumn<Object?>>[users.email],
        );

        expect(insert.statement.fragments, <String>[
          'INSERT INTO "users" ("email", "active") VALUES (',
          ', ',
          ') ON CONFLICT ("email") DO NOTHING',
        ]);
        expect(_values(insert.statement), <Object?>['ada@example.com', true]);
        expect(insert.statement.kind, SqlStatementKind.write);
        expect(insert.statement.dialect, dialect);

        final returning = insert.returning(users.projection);
        expect(returning.statement.fragments, <String>[
          'INSERT INTO "users" ("email", "active") VALUES (',
          ', ',
          ') ON CONFLICT ("email") DO NOTHING '
              'RETURNING "id", "email", "nickname", "active"',
        ]);
        expect(_values(returning.statement), <Object?>[
          'ada@example.com',
          true,
        ]);
        expect(returning.statement.kind, SqlStatementKind.rowReturning);
        expect(returning.statement.dialect, dialect);
      });
    }

    test('rejects MySQL conflict inserts without reading inputs', () {
      final users = _Users();
      var valuesRead = false;
      var targetRead = false;

      Iterable<SqlAssignment> values() sync* {
        valuesRead = true;
        yield users.email.set('ada@example.com');
      }

      Iterable<SqlTableColumn<Object?>> target() sync* {
        targetRead = true;
        yield users.email;
      }

      expect(
        () => const SqlQueries(
          SqlDialect.mysql,
        ).insertOnConflictDoNothing(users, values(), target: target()),
        _throwsSql(SqlErrorCode.unsupported),
      );
      expect(valuesRead, isFalse);
      expect(targetRead, isFalse);
    });
  });

  group('single-row terminals', () {
    for (final dialect in SqlDialect.values) {
      for (final terminal in <String>['one', 'oneOrNull']) {
        test('${dialect.name} $terminal limits cardinality reads without '
            'changing all', () async {
          final users = _Users();
          final queries = SqlQueries(dialect);

          final unbounded = queries.selectTable(users);
          final unboundedExecutor = _RecordingExecutor(<SqlRow>[_userRow(1)]);
          if (terminal == 'one') {
            await unbounded.one(unboundedExecutor);
          } else {
            await unbounded.oneOrNull(unboundedExecutor);
          }
          expect(
            unboundedExecutor.statement!.fragments.last,
            endsWith(' LIMIT 2'),
          );

          final limited = queries.selectTable(users, limit: 20, offset: 7);
          final original = limited.statement;
          final limitedExecutor = _RecordingExecutor(<SqlRow>[_userRow(1)]);
          if (terminal == 'one') {
            await limited.one(limitedExecutor);
          } else {
            await limited.oneOrNull(limitedExecutor);
          }
          expect(
            limitedExecutor.statement!.fragments.last,
            endsWith(' LIMIT 2 OFFSET 7'),
          );
          expect(original.fragments.last, endsWith(' LIMIT 20 OFFSET 7'));

          final allExecutor = _RecordingExecutor(<SqlRow>[_userRow(1)]);
          await limited.all(allExecutor);
          expect(allExecutor.statement, same(original));
        });

        test('${dialect.name} $terminal preserves limits up to two', () async {
          final users = _Users();
          final queries = SqlQueries(dialect);

          for (final limit in <int>[0, 1, 2]) {
            final read = queries.selectTable(users, limit: limit, offset: 7);
            final executor = _RecordingExecutor(<SqlRow>[_userRow(1)]);
            if (terminal == 'one') {
              await read.one(executor);
            } else {
              await read.oneOrNull(executor);
            }
            expect(executor.statement, same(read.statement));
            expect(
              executor.statement!.fragments.last,
              endsWith(' LIMIT $limit OFFSET 7'),
            );
          }
        });
      }
    }

    for (final terminal in <String>['one', 'oneOrNull']) {
      test(
        '$terminal does not decode rows before cardinality is known',
        () async {
          final users = _Users();
          var decodeCalls = 0;
          final read = const SqlQueries(SqlDialect.sqlite).select(
            from: users,
            projection: SqlProjection<String>(
              <SqlSelection<Object?>>[users.email],
              (row) {
                decodeCalls++;
                return users.email.read(row, 0);
              },
            ),
          );
          final executor = _RecordingExecutor(<SqlRow>[
            _emailRow(1),
            _emailRow(2),
          ]);

          if (terminal == 'one') {
            await expectLater(read.one(executor), throwsStateError);
          } else {
            await expectLater(read.oneOrNull(executor), throwsStateError);
          }

          expect(decodeCalls, 0);
        },
      );
    }
  });

  group('relational reads', () {
    for (final dialect in SqlDialect.values) {
      test('${dialect.name} qualifies a typed LEFT JOIN', () {
        final posts = _Posts();
        final users = _Users();
        final authorEmail = users.email.optional.as('author_email');
        final projection = SqlProjection<({String title, String? authorEmail})>(
          <SqlSelection<Object?>>[posts.title, authorEmail],
          (row) => (
            title: posts.title.read(row, 0),
            authorEmail: authorEmail.read(row, 1),
          ),
        );
        final quote = dialect == SqlDialect.mysql ? '`' : '"';

        final select = SqlQueries(dialect).select(
          from: posts,
          joins: <SqlJoin>[
            SqlJoin.left(users, on: posts.authorId.equalsColumn(users.id)),
          ],
          projection: projection,
          where: users.active.equals(true).or(posts.authorId.isNull),
          orderBy: <SqlOrder>[users.email.ascending],
        );

        expect(select.statement.fragments, <String>[
          'SELECT ${quote}t0$quote.${quote}title$quote, '
              '${quote}t1$quote.${quote}email$quote AS '
              '${quote}author_email$quote FROM ${quote}posts$quote AS '
              '${quote}t0$quote LEFT JOIN ${quote}users$quote AS '
              '${quote}t1$quote ON ${quote}t0$quote.${quote}author_id$quote = '
              '${quote}t1$quote.${quote}id$quote WHERE '
              '(${quote}t1$quote.${quote}active$quote = ',
          ' OR ${quote}t0$quote.${quote}author_id$quote IS NULL) ORDER BY '
              '${quote}t1$quote.${quote}email$quote ASC',
        ]);
        expect(_values(select.statement), <Object?>[true]);
      });
    }

    test('uses distinct table instances for a qualified self join', () {
      final employee = _Users();
      final manager = _Users();
      final managerEmail = manager.email.as('manager_email');

      final select = const SqlQueries(SqlDialect.sqlite).select(
        from: employee,
        joins: <SqlJoin>[
          SqlJoin.inner(manager, on: employee.id.equalsColumn(manager.id)),
        ],
        projection: SqlProjection.column(managerEmail),
      );

      expect(
        select.statement.fragments.single,
        'SELECT "t1"."email" AS "manager_email" FROM "users" AS "t0" '
        'INNER JOIN "users" AS "t1" ON "t0"."id" = "t1"."id"',
      );
    });

    test('qualifies schema tables and result aliases independently', () {
      final parent = _NamedTable(
        'parents',
        schema: 'tenant',
        columnName: 'external_id',
      );
      final child = _NamedTable(
        'children',
        schema: 'tenant',
        columnName: 'parent_id',
      );

      final select = const SqlQueries(SqlDialect.postgres).select(
        from: child,
        joins: <SqlJoin>[
          SqlJoin.inner(parent, on: child.value.equalsColumn(parent.value)),
        ],
        projection: SqlProjection.column(parent.value.as('parent_external_id')),
      );

      expect(
        select.statement.fragments.single,
        'SELECT "t1"."external_id" AS "parent_external_id" '
        'FROM "tenant"."children" AS "t0" '
        'INNER JOIN "tenant"."parents" AS "t1" '
        'ON "t0"."parent_id" = "t1"."external_id"',
      );
    });

    test('builds incremental scope across three joined tables', () {
      final posts = _NamedTable('posts', columnName: 'author_key');
      final authors = _NamedTable('authors', columnName: 'key');
      final teams = _NamedTable('teams', columnName: 'author_key');

      final select = const SqlQueries(SqlDialect.sqlite).select(
        from: posts,
        joins: <SqlJoin>[
          SqlJoin.inner(authors, on: posts.value.equalsColumn(authors.value)),
          SqlJoin.inner(teams, on: authors.value.equalsColumn(teams.value)),
        ],
        projection: SqlProjection.column(teams.value.as('team_author')),
      );

      expect(
        select.statement.fragments.single,
        'SELECT "t2"."author_key" AS "team_author" FROM "posts" AS "t0" '
        'INNER JOIN "authors" AS "t1" ON "t0"."author_key" = "t1"."key" '
        'INNER JOIN "teams" AS "t2" ON "t1"."key" = "t2"."author_key"',
      );
    });
  });

  group('mutations', () {
    test('compiles UPDATE, DELETE, and RETURNING without placeholders', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      final update = queries
          .updateWhere(users, <SqlAssignment>[
            users.email.set('grace@example.com'),
            users.active.set(false),
          ], where: users.id.equals(7))
          .returning(users.projection);
      expect(update.statement.fragments, <String>[
        'UPDATE "users" SET "email" = ',
        ', "active" = ',
        ' WHERE "id" = ',
        ' RETURNING "id", "email", "nickname", "active"',
      ]);
      expect(_values(update.statement), <Object?>[
        'grace@example.com',
        false,
        7,
      ]);
      expect(update.statement.kind, SqlStatementKind.rowReturning);
      expect(update.statement.dialect, SqlDialect.sqlite);

      final delete = queries.deleteWhere(
        users,
        where: users.email.notEquals('root@example.com'),
      );
      expect(delete.statement.fragments, <String>[
        'DELETE FROM "users" WHERE "email" <> ',
        '',
      ]);
      expect(_values(delete.statement), <Object?>['root@example.com']);
      expect(delete.statement.kind, SqlStatementKind.write);
      expect(delete.statement.dialect, SqlDialect.sqlite);

      final columnDelete = queries.deleteWhere(
        users,
        where: users.email.notEqualsColumn(users.email),
      );
      expect(
        columnDelete.statement.fragments.single,
        'DELETE FROM "users" WHERE "email" <> "email"',
      );

      final aliasedReturning = queries
          .insert(users, <SqlAssignment>[users.email.set('alias@example.com')])
          .returning(
            SqlProjection.column(users.email.optional.as('returned_email')),
          );
      expect(aliasedReturning.statement.fragments, <String>[
        'INSERT INTO "users" ("email") VALUES (',
        ') RETURNING "email" AS "returned_email"',
      ]);
      expect(aliasedReturning.statement.dialect, SqlDialect.sqlite);

      for (final fragment in <String>[
        ...update.statement.fragments,
        ...delete.statement.fragments,
        ...columnDelete.statement.fragments,
        ...aliasedReturning.statement.fragments,
      ]) {
        expect(fragment, isNot(contains('?')));
        expect(fragment, isNot(matches(RegExp(r'\$\d+'))));
      }
    });

    test('requires visible confirmation for full-table mutations', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      final update = queries.updateAll(users, <SqlAssignment>[
        users.active.set(false),
      ], confirm: allRows);
      expect(update.statement.fragments, <String>[
        'UPDATE "users" SET "active" = ',
        '',
      ]);

      final delete = queries.deleteAll(users, confirm: allRows);
      expect(delete.statement.fragments.single, 'DELETE FROM "users"');
    });
  });

  group('validation', () {
    test('rejects columns owned by another table', () {
      final users = _Users();
      final other = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        () => queries.insert(users, <SqlAssignment>[
          other.email.set('ada@example.com'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => queries.selectTable(users, where: other.id.equals(1)),
        throwsArgumentError,
      );
      expect(
        () =>
            queries.selectTable(users, orderBy: <SqlOrder>[other.id.ascending]),
        throwsArgumentError,
      );
      expect(
        () => queries.select(from: users, projection: other.projection),
        throwsArgumentError,
      );
      expect(
        () => queries
            .insert(users, <SqlAssignment>[users.email.set('ada@example.com')])
            .returning(other.projection),
        throwsArgumentError,
      );
    });

    test('rejects duplicate and empty UPDATE assignments', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        () => queries.updateWhere(users, <SqlAssignment>[
          users.email.set('first@example.com'),
          users.email.set('second@example.com'),
        ], where: users.id.equals(1)),
        throwsArgumentError,
      );
      expect(
        () =>
            queries.updateAll(users, const <SqlAssignment>[], confirm: allRows),
        throwsArgumentError,
      );
    });

    test('validates targeted conflict inserts', () {
      final users = _Users();
      final other = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        () => queries.insertOnConflictDoNothing(
          users,
          const <SqlAssignment>[],
          target: <SqlTableColumn<Object?>>[users.email],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.insertOnConflictDoNothing(users, <SqlAssignment>[
          users.email.set('ada@example.com'),
        ], target: const <SqlTableColumn<Object?>>[]),
        throwsArgumentError,
      );
      expect(
        () => queries.insertOnConflictDoNothing(
          users,
          <SqlAssignment>[users.email.set('ada@example.com')],
          target: <SqlTableColumn<Object?>>[users.email, users.email],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.insertOnConflictDoNothing(
          users,
          <SqlAssignment>[users.email.set('ada@example.com')],
          target: <SqlTableColumn<Object?>>[other.email],
        ),
        throwsArgumentError,
      );
    });

    test('normalizes NULL equality and rejects ordered NULL comparisons', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        queries
            .selectTable(users, where: users.nickname.equals(null))
            .statement
            .fragments
            .single,
        'SELECT "id", "email", "nickname", "active" '
        'FROM "users" WHERE "nickname" IS NULL',
      );
      expect(
        queries
            .selectTable(users, where: users.nickname.notEquals(null))
            .statement
            .fragments
            .single,
        'SELECT "id", "email", "nickname", "active" '
        'FROM "users" WHERE "nickname" IS NOT NULL',
      );
      expect(() => users.nickname.lessThan(null), throwsArgumentError);
    });

    test('rejects invalid pagination', () {
      final users = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(() => queries.selectTable(users, limit: -1), throwsArgumentError);
      expect(
        () => queries.selectTable(users, limit: 1, offset: -1),
        throwsArgumentError,
      );
      expect(() => queries.selectTable(users, offset: 1), throwsArgumentError);
    });

    test('rejects invalid relational scopes', () {
      final posts = _Posts();
      final users = _Users();
      final outsider = _Users();
      const queries = SqlQueries(SqlDialect.sqlite);

      expect(
        () => queries.selectTable(
          posts,
          joins: <SqlJoin>[
            SqlJoin.inner(posts, on: posts.id.equalsColumn(posts.id)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.selectTable(
          posts,
          joins: <SqlJoin>[
            SqlJoin.inner(users, on: users.id.equalsColumn(users.id)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.selectTable(
          posts,
          joins: <SqlJoin>[
            SqlJoin.inner(users, on: posts.id.equalsColumn(posts.id)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.select(
          from: posts,
          joins: <SqlJoin>[
            SqlJoin.inner(users, on: users.id.equalsColumn(outsider.id)),
          ],
          projection: posts.projection,
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.selectTable(
          posts,
          joins: <SqlJoin>[
            SqlJoin.inner(users, on: outsider.id.equalsColumn(users.id)),
            SqlJoin.inner(outsider, on: users.id.equalsColumn(outsider.id)),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.select(
          from: posts,
          joins: <SqlJoin>[
            SqlJoin.inner(users, on: posts.authorId.equalsColumn(users.id)),
          ],
          projection: outsider.projection,
        ),
        throwsArgumentError,
      );
      expect(
        () => queries.updateWhere(users, <SqlAssignment>[
          users.active.set(false),
        ], where: users.id.equalsColumn(outsider.id)),
        throwsArgumentError,
      );
      expect(() => users.email.as(''), throwsArgumentError);
    });
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

final class _NamedTable extends SqlTable<String> {
  _NamedTable(super.name, {super.schema, required String columnName}) {
    value = column<String>(columnName, sqlText);
  }

  late final SqlTableColumn<String> value;

  @override
  late final SqlProjection<String> projection = SqlProjection.column(value);
}

List<Object?> _values(BoundSql statement) => <Object?>[
  for (final value in statement.values) value.value,
];

Matcher _throwsSql(SqlErrorCode code) =>
    throwsA(isA<SqlException>().having((error) => error.code, 'code', code));

SqlRow _userRow(int id) => SqlRow(
  <String>['id', 'email', 'nickname', 'active'],
  <SqlValue>[
    SqlValue.integer(id),
    SqlValue.text('user$id@example.com'),
    const SqlValue.nullValue(),
    const SqlValue.boolean(true),
  ],
);

SqlRow _emailRow(int id) =>
    SqlRow(<String>['email'], <SqlValue>[SqlValue.text('user$id@example.com')]);

final class _RecordingExecutor implements SqlExecutor {
  _RecordingExecutor(this.rows);

  final List<SqlRow> rows;
  BoundSql? statement;

  @override
  Future<List<T>> query<T>(
    BoundSql statement,
    T Function(SqlRow row) decode,
  ) async {
    this.statement = statement;
    return <T>[for (final row in rows) decode(row)];
  }

  @override
  Future<SqlWriteResult> execute(BoundSql statement) =>
      throw UnsupportedError('The recording executor only supports queries.');
}
