import 'component.dart';
import 'element.dart';
import 'element_impl.dart';
import 'owner_impl.dart';
import 'setup.dart';

/// Internal, Component impl
class ComponentImpl<Props> implements Component<Props> {
  ComponentImpl(this.setup);

  final Setup<Props> setup;

  @override
  String? displayName;

  @override
  Element call(Props props) {
    final parent = evalOwner;
    final element = ElementImpl(this);
    final owner = OwnerImpl(element, parent);

    evalOwner = element.owner = owner;

    throw element;
  }
}
