import 'package:flutter/widgets.dart';

abstract interface class Element {}

typedef Render = Element Function();

typedef RenderBuilder = Element Function(BuildContext context);
Render defineRender(RenderBuilder builder) {
  throw UnimplementedError();
}
