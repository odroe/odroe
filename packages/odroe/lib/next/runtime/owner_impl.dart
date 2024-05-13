import 'element.dart';
import 'element_impl.dart';

int uid = 0;
Owner? evalOwner;

/// Internal, Owner impl
class OwnerImpl implements Owner {
  OwnerImpl(this.element, [this.parent]);

  @override
  Owner? parent;

  @override
  final ElementImpl element;
}
