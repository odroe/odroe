class Depend {
  Depend();

  bool dirty = true;

  Depend? next;
  Depend? prev;
  Depend? head;
  Depend? tail;

  void track() {
    throw UnimplementedError();
  }

  void trigger() {
    throw UnimplementedError();
  }

  void notify() {
    throw UnimplementedError();
  }
}
