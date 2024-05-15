import 'dart:developer' show log;

/// Level is warning, @see https://pub.dev/documentation/logging/latest/logging/Level/WARNING-constant.html
void warn(String message) => log('[odroe] $message', level: 900);
