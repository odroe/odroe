import 'package:flutter/widgets.dart' show BuildContext;

import 'element.dart';

typedef Render = Element Function();
typedef RenderBuilder = Element Function(BuildContext context);

Render defineRender(RenderBuilder builder) {
  throw UnimplementedError();
}
