import 'package:odroe/database.dart';
import 'package:odroe/src/database/dialect.dart' show requireSqlDialect;
import 'package:test/test.dart';

void main() {
  test('accepts unpinned and matching SQL dialects', () {
    for (final expected in SqlDialect.values) {
      expect(
        () => requireSqlDialect(null, expected, 'Database'),
        returnsNormally,
      );
      expect(
        () => requireSqlDialect(expected, expected, 'Database'),
        returnsNormally,
      );
    }
  });

  test('reports only the database and mismatched dialect', () {
    expect(
      () => requireSqlDialect(
        SqlDialect.mysql,
        SqlDialect.postgres,
        'PostgreSQL',
      ),
      throwsA(
        isA<SqlException>()
            .having((error) => error.code, 'code', SqlErrorCode.unsupported)
            .having(
              (error) => error.message,
              'message',
              'PostgreSQL cannot execute SQL compiled for the mysql dialect.',
            ),
      ),
    );
  });
}
