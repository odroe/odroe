import 'public.dart' as public;

abstract interface class Derived<T> implements public.Derived<T> {}

abstract interface class Node {
  abstract int version;
  Subscriber get subscriber;
  List<Node> get dependents;
  List<Subscriber> get subscribers;
}

abstract interface class Subscriber {
  abstract int flags;
  List<Node> get dependents;
  List<Subscriber> get children;
  Derived? notify();
}

abstract interface class Dependent {
  abstract int version;
  List<Node> get subscribers;
  Derived? get derived;

  Node? track();
  void trigger();
  void notify();
}

abstract interface class Effect<T> implements public.Effect<T>, Subscriber {
  abstract void Function()? cleanup;
  abstract final T Function() runner;
  void runIfDirty();
}

abstract interface class Scope implements public.Scope {
  List<Effect> get effects;
  List<Scope> get scopes;
  List<void Function()> get cleanups;

  abstract covariant Scope? parent;
  abstract int? index;

  void on();
  void off();
}
