import 'package:flutter/widgets.dart' show BuildContext;

import 'element.dart';

typedef Render<Props> = Element<Props> Function();
typedef RenderBuilder = Element<void> Function(BuildContext context);

Render<void> defineRender(RenderBuilder builder) {
  throw UnimplementedError();
}
