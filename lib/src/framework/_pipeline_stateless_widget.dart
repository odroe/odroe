import 'package:flutter/widgets.dart';

import 'functional_widget_pipe.dart';

class FunctionalPipeWidget extends StatelessWidget
    implements FunctionalWidgetPipe {
  // ignore: prefer_const_constructors_in_immutables
  FunctionalPipeWidget({super.key});

  @protected
  late final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);

  @override
  Widget operator |(WidgetBuilder builder) => this..builder = builder;

  @override
  FunctionalWidgetPipe operator +(Key key) => FunctionalPipeWidget(key: key);
}
