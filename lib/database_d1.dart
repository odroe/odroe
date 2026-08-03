/// Preview Cloudflare D1 driver for Odroe's typed SQL transport.
///
/// Documented transient failures map to `SqlErrorCode.unavailable`; the driver
/// never retries an operation automatically.
library;

export 'database.dart';
export 'src/database_d1/database.dart' show D1SqlDatabase;
