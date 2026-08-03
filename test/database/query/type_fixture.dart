import 'package:odroe/database.dart';

final class TypeFixtureTable extends SqlTable<({String email, bool active})> {
  TypeFixtureTable() : super('type_fixture');

  late final SqlTableColumn<String> email = column<String>('email', sqlText);
  late final SqlTableColumn<bool> active = column<bool>('active', sqlBool);
  late final SqlTableColumn<int> id = column<int>('id', sqlInt);
  late final SqlTableColumn<int?> ownerId = column<int?>(
    'owner_id',
    nullable(sqlInt),
  );

  @override
  late final SqlProjection<({String email, bool active})> projection =
      SqlProjection<({String email, bool active})>(
        columns: [email, active],
        decode: (row) => (email: row.read(email), active: row.read(active)),
      );
}

List<SqlPredicate> validPredicates(TypeFixtureTable table) => <SqlPredicate>[
  table.id.equalsColumn(table.ownerId),
  table.ownerId.equalsColumn(table.id),
  table.email.isIn(<String>['ada@example.com']),
  table.ownerId.isNotIn(<int?>[1, null]),
];

SqlProjection<String?> validOptionalProjection(TypeFixtureTable table) =>
    SqlProjection.column(table.email.optional);

SqlRead<int> validCountFixture(TypeFixtureTable table) => const SqlQueries(
  SqlDialect.sqlite,
).countRows(table, where: table.active.equals(true));

SqlWrite validNumericUpdateFixture(TypeFixtureTable table) =>
    const SqlQueries(SqlDialect.sqlite).updateWhere(
      table,
      <SqlUpdateAssignment>[table.id.incrementBy(1), table.active.set(false)],
      where: table.id.equals(42),
    );

SqlWrite insertAssignmentFixture(
  TypeFixtureTable table,
  SqlAssignment assignment,
) => const SqlQueries(
  SqlDialect.sqlite,
).insert(table, <SqlAssignment>[assignment]);

SqlRead<({String email, bool active})> validTypeFixture() {
  final table = TypeFixtureTable();
  final assignments = <SqlAssignment>[
    table.email.set('ada@example.com'),
    table.active.set(true),
  ];
  return const SqlQueries(
    SqlDialect.sqlite,
  ).insert(table, assignments).returning(table.projection);
}
