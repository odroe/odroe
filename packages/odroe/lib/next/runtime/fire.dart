import 'package:flutter/widgets.dart' hide Element;

import 'element.dart';

typedef FireMaker = Widget Function();

Element fire(FireMaker maker) {
  throw UnimplementedError();
}
