import 'package:flutter/widgets.dart';

final class NullWidget extends Widget {
  const NullWidget() : super(key: null);

  @override
  Element createElement() => throw UnimplementedError();
}
