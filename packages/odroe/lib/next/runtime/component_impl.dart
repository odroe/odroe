import 'component.dart';
import 'element.dart';
import 'setup.dart';

/// Internal, Component impl
class ComponentImpl<P> implements Component<P> {
  ComponentImpl(this.setup);

  final Setup<P> setup;

  @override
  String? displayName;

  @override
  Element call(P props) {
    // TODO: implement call
    throw UnimplementedError();
  }
}
