/// Portable metadata returned by one SQL write.
final class SqlWriteResult {
  /// Creates write metadata with the number of changed rows and generated ID.
  SqlWriteResult({required this.affectedRows, this.lastInsertId}) {
    if (affectedRows < 0) {
      throw ArgumentError.value(
        affectedRows,
        'affectedRows',
        'Must not be negative.',
      );
    }
    final id = lastInsertId;
    if (id != null && id < 0) {
      throw ArgumentError.value(id, 'lastInsertId', 'Must not be negative.');
    }
  }

  /// Number of rows changed by the statement.
  final int affectedRows;

  /// Auto-generated integer key reported by the write, when available.
  ///
  /// Drivers return this from the same connection and operation as the write.
  /// Applications that need portable non-integer IDs should generate them.
  final int? lastInsertId;
}
