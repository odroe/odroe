import 'dart:developer';

bool get dev => NativeRuntime.buildId == null;

void warn(String message) {
  log(message, name: '[oref] warning', level: 900);
}
