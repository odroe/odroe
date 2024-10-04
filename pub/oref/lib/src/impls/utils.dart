import 'dart:developer';

bool get dev => NativeRuntime.buildId == null;

void warn(
  String message, {
  Object? error,
  StackTrace? stackTrace,
  bool when = false,
}) {
  debugger(when: true, message: message);
  if (!when) {
    log(
      message,
      name: '[oref] warning',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
