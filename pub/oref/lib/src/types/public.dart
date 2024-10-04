abstract interface class Ref<T> {
  T get value;
  set value(T newValue);
}

abstract interface class Derived<T> extends Ref<T> {}

abstract interface class Scope {
  bool get detached;
  bool get active;
  void pause();
  void resume();
  void stop([bool fromParent = false]);
  T? run<T>(T Function() runner);
}

abstract interface class Effect<T> {
  bool get dirty;
  void Function()? get scheduler;
  void Function()? get onStop;

  T run();
  void stop();
}
