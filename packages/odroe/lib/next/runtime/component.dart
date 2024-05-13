import 'element.dart';
import 'setup.dart';

abstract interface class Component<Props> {
  String? displayName;

  Element call(covariant Props props) {
    throw UnimplementedError();
  }
}

extension ComponentWithoutProps on Component<void> {
  Element get zero => call(null);
}

/// Internal, Component impl
class ComponentImpl<Props> implements Component<Props> {
  ComponentImpl(this.setup);

  final Setup<Props> setup;

  @override
  String? displayName;

  @override
  Element call(Props props) {
    final depthOwner = findDepthOwner();
    if (depthOwner != null) {
      if (depthOwner.element.component == this) {
        depth++;
        evalOwner = depthOwner;

        // TODO: Compare whether Props have been updated, and if so, notify the owner to rebuild
        return depthOwner.element;
      }

      depthOwner.unmount();
      evalOwner = depthOwner.prev;
      depthOwner.next = null;
    }

    final parent = evalOwner;
    final element = ElementImpl(this);
    final owner = OwnerImpl(element, depth);

    owner.prev = parent;
    evalOwner = owner;
    depth++;

    return element;
  }
}
