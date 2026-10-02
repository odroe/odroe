/// Preview native MySQL and MariaDB support for Odroe database contracts.
///
/// Includes an eager serialized connection and an owned lazy bounded pool.
library;

export 'database.dart';
export 'src/database_mysql/database.dart' show MysqlDatabase;
