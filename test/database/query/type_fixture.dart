import 'package:odroe/database.dart';

final class TypeFixtureTable extends SqlTable<({String email, bool active})> {
  TypeFixtureTable() : super('type_fixture');

  late final SqlTableColumn<String> email = column<String>('email', sqlText);
  late final SqlTableColumn<bool> active = column<bool>('active', sqlBool);

  @override
  late final SqlProjection<({String email, bool active})> projection =
      SqlProjection<({String email, bool active})>(<SqlTableColumn<Object?>>[
        email,
        active,
      ], (row) => (email: email.read(row, 0), active: active.read(row, 1)));
}

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
