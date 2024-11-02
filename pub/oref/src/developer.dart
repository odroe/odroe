import 'dart:developer';

import 'utils.dart';

bool dev = NativeRuntime.buildId == null;
String brand = '\x1B[45m\x1B[33m\x1B[1m Oref \x1B[0m';
bool color = true;

main() {
  warn('haha', [
    1,
    {1: 2}
  ]);
}
