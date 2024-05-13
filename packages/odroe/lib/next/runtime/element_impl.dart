import 'component.dart';
import 'element.dart';

/// Internal, [Element] impl.
class ElementImpl<Props> implements Element<Props> {
  ElementImpl(this.component);

  @override
  final Component<Props> component;

  @override
  Owner? owner;
}
