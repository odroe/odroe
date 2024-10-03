import 'public.dart' as public;

abstract interface class Link {
  Dep get dep;
  Sub get sub;

  Link? prevDep;
  Link? nextDep;
  Link? prevSub;
  Link? nextSub;

  abstract int version;
}

abstract interface class Sub {
  Link? deps;
  Link? depsTail;
  Sub? next;
  abstract int flags;
  Derived? notify();
}

abstract interface class Dep {
  abstract int vrsion;
  Link? activeLink;
  Link? subs;
  Derived? get derived;

  Link? track();
  void trigger();
  void notify();
}

abstract interface class Ref<T> implements public.Ref<T> {
  Dep get dep;
}

abstract interface class Derived<T> implements public.Derived<T>, Sub, Ref<T> {
  abstract int version;
}

abstract interface class Effect<T> implements public.Effect<T>, Sub {
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
