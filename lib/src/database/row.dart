import 'codec.dart';
import 'error.dart';

/// One immutable, ordered SQL result row.
///
/// Duplicate column names are preserved. Decode by index so joins and repeated
/// labels never overwrite data.
final class SqlRow {
  /// Creates a row from equally sized [columns] and [values].
  ///
  /// Both lists are defensively copied.
  factory SqlRow(List<String> columns, List<SqlValue> values) {
    final copiedColumns = List<String>.unmodifiable(columns);
    final copiedValues = List<SqlValue>.unmodifiable(values);
    if (copiedColumns.length != copiedValues.length) {
      throw ArgumentError(
        'SqlRow requires the same number of columns and values.',
      );
    }
    return SqlRow._(copiedColumns, copiedValues);
  }

  const SqlRow._(this._columns, this._values);

  final List<String> _columns;
  final List<SqlValue> _values;

  /// Number of ordered columns in this row.
  int get length => _values.length;

  /// Returns the column label at [index].
  String nameAt(int index) {
    _checkIndex(index);
    return _columns[index];
  }

  /// Returns the normalized SQL value at [index].
  SqlValue valueAt(int index) {
    _checkIndex(index);
    return _values[index];
  }

  /// Decodes the value at [index] with [codec].
  ///
  /// When [expectedName] is present, the actual column label must match it.
  T read<T>(int index, SqlCodec<T> codec, {String? expectedName}) {
    _checkIndex(index);
    final actualName = _columns[index];
    if (expectedName != null && actualName != expectedName) {
      throw SqlException(
        SqlErrorCode.invalidRow,
        'Column $index is "$actualName", expected "$expectedName".',
      );
    }
    try {
      return codec.decode(_values[index]);
    } on Exception catch (error) {
      throw SqlException(
        SqlErrorCode.invalidRow,
        'Cannot decode column $index ("$actualName").',
        cause: error,
      );
    }
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= length) {
      throw SqlException(
        SqlErrorCode.invalidRow,
        'Column index $index is outside a row with $length columns.',
      );
    }
  }
}

/// A named SQL column with one Dart value codec.
final class SqlColumn<T> {
  /// Creates a typed column.
  const SqlColumn(this.name, this.codec) : assert(name != '');

  /// Expected result label and schema column name.
  final String name;

  /// Codec used to bind and decode this column.
  final SqlCodec<T> codec;

  /// Encodes [value] as a bound parameter.
  SqlValue bind(T value) {
    try {
      return codec.encode(value);
    } on Exception catch (error) {
      throw SqlException(
        SqlErrorCode.invalidValue,
        'Cannot bind column "$name".',
        cause: error,
      );
    }
  }

  /// Decodes this column from [row] at [index].
  T read(SqlRow row, int index) => row.read(index, codec, expectedName: name);

  /// Creates a query-local alias using the same [codec].
  SqlColumn<T> as(String alias) {
    if (alias.isEmpty) {
      throw ArgumentError.value(alias, 'alias', 'Alias must not be empty.');
    }
    return SqlColumn<T>(alias, codec);
  }
}
