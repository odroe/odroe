import 'package:odroe/database.dart';
import 'package:test/test.dart';

void main() {
  test('projection reads duplicate labels by selection identity', () {
    final left = _Ids('left_ids');
    final right = _Ids('right_ids');
    final projection = SqlProjection<({int left, int right})>(
      columns: [right.id, left.id],
      decode: (row) => (left: row.read(left.id), right: row.read(right.id)),
    );

    final result = projection.decode(
      SqlRow(
        <String>['id', 'id'],
        <SqlValue>[const SqlValue.integer(22), const SqlValue.integer(11)],
      ),
    );

    expect(result, (left: 11, right: 22));
  });

  test('projection keeps aliases and optional selections distinct', () {
    final people = _People();
    final optionalAuthor = people.displayName.optional.as('author_name');
    final projection = SqlProjection<({String name, String? author})>(
      columns: [optionalAuthor, people.displayName],
      decode: (row) => (
        name: row.read(people.displayName),
        author: row.read(optionalAuthor),
      ),
    );

    final result = projection.decode(
      SqlRow(
        <String>['author_name', 'name'],
        <SqlValue>[const SqlValue.nullValue(), const SqlValue.text('Ada')],
      ),
    );

    expect(result, (name: 'Ada', author: null));
  });

  test('projection rejects a selection outside its columns', () {
    final selected = _Ids('selected_ids');
    final outside = _Ids('outside_ids');
    final projection = SqlProjection<int>(
      columns: [selected.id],
      decode: (row) => row.read(outside.id),
    );

    expect(
      () => projection.decode(
        SqlRow(<String>['id'], <SqlValue>[const SqlValue.integer(1)]),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('is not part of this SQL projection'),
        ),
      ),
    );
  });

  test('projection rejects the same selection identity twice', () {
    final ids = _Ids('ids');

    expect(
      () => SqlProjection<int>(columns: [ids.id, ids.id], decode: (_) => 1),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('is used more than once'),
        ),
      ),
    );
  });

  test('projection validates row width before decoding', () {
    final ids = _Ids('ids');
    var decodeCalls = 0;
    final projection = SqlProjection<int>(
      columns: [ids.id],
      decode: (row) {
        decodeCalls++;
        return row.read(ids.id);
      },
    );

    expect(
      () => projection.decode(
        SqlRow(
          <String>['id', 'id'],
          <SqlValue>[const SqlValue.integer(1), const SqlValue.integer(2)],
        ),
      ),
      throwsA(
        isA<SqlException>()
            .having((error) => error.code, 'code', SqlErrorCode.invalidRow)
            .having(
              (error) => error.message,
              'message',
              contains('expected 1 column, received 2'),
            ),
      ),
    );
    expect(decodeCalls, 0);
  });
}

final class _Ids extends SqlTable<int> {
  _Ids(super.name);

  late final SqlTableColumn<int> id = column<int>('id', sqlInt);

  @override
  late final SqlProjection<int> projection = SqlProjection.column(id);
}

final class _People extends SqlTable<String> {
  _People() : super('people');

  late final SqlTableColumn<String> displayName = column<String>(
    'name',
    sqlText,
  );

  @override
  late final SqlProjection<String> projection = SqlProjection.column(
    displayName,
  );
}
