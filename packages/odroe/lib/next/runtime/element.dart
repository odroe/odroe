abstract interface class Element {
  Owner? get owner;
}

abstract interface class Owner {
  abstract final Element element;
  abstract final Owner? next;
  abstract final Owner? prev;
}
