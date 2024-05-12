import 'package:flutter/foundation.dart' show debugPrintThrottled;
import 'package:flutter/material.dart';

void warn<T>(String message, [T? args]) {
  if (args != null) {
    return debugPrintThrottled('[Odroe warn] $message $args');
  }

  debugPrintThrottled('[Odroe warn] $message');
}

final demo = WeakMap();
