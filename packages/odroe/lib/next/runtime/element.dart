import 'component.dart';

abstract interface class Element<Props> {
  Owner? get owner;
  Component<Props> get component;
}

abstract interface class Owner<Props> {
  Element<Props> get element;
  Owner? parent;
}
