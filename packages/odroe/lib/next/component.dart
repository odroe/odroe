abstract interface class Component {
  Iterable get props;
  SetupCallback get setup;
}

typedef ComponentRender = Component Function();
typedef SetupCallback = ComponentRender Function();

// Internal, Component impl.
class ComponentInstance implements Component {
  @override
  late Iterable props;

  @override
  late SetupCallback setup;
}

ComponentInstance? evalComponent;

ComponentInstance getOrCreateComponentInstance() => switch (evalComponent) {
      ComponentInstance component => component,
      _ => ComponentInstance(),
    };

Component setup(SetupCallback fn) {
  final component = getOrCreateComponentInstance();
  component.setup = fn;
  evalComponent = null;

  return component;
}

void defineProps(Iterable props) {
  final component = getOrCreateComponentInstance();
  component.props = props;
}
