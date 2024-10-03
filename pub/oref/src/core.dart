import '_utils.dart';
import '_warning.dart';
import 'types.dart';

bool shouldTrack = true;
Sub? activeSub;
int globalVersion = 0;
int batchDepth = 0;
Sub? batchedSub;

void startBatch() {
  print("startBatch called");
  batchDepth++;
}

void endBatch() {
  print("endBatch called");
  if (--batchDepth > 0) {
    print("batchDepth > 0, returning early");
    return;
  }

  Object? error;
  while (batchedSub != null) {
    Sub? current = batchedSub, next;
    while (current != null) {
      if (!current.flags.contains(Flags.active)) {
        current.flags &= ~Flags.notified;
      }

      current = current.next;
    }

    current = batchedSub;
    batchedSub = null;

    while (current != null) {
      next = current.next;
      current.next = null;
      current.flags &= ~Flags.notified;
      if (current.flags.contains(Flags.active)) {
        try {
          print("Triggering effect");
          (current as ReactiveEffect).trigger();
        } catch (e) {
          print("Error in effect: $e");
          error ??= e;
        }
      }

      current = next;
    }
  }

  if (error != null) {
    throw error;
  }
}

extension type const Flags._(int _) implements int {
  static const active = Flags._(1 << 0);
  static const running = Flags._(1 << 1);
  static const tracking = Flags._(1 << 2);
  static const notified = Flags._(1 << 3);
  static const dirty = Flags._(1 << 4);
  static const allowRecurse = Flags._(1 << 5);
  static const paused = Flags._(1 << 6);

  Flags operator |(Flags other) => Flags._(_ | other);
  Flags operator &(Flags other) => Flags._(_ & other);
  Flags operator ~() => Flags._(~_);

  bool contains(Flags other) => (_ & other) != 0;
}

class Link {
  Link(this.sub, this.dep) : version = dep.version;

  int version;
  final Sub sub;
  final Dep dep;

  Link? prevDep;
  Link? nextDep;
  Link? prevSub;
  Link? nextSub;
  Link? prevActiveLink;

  void removeSub([bool sort = false]) {
    if (prevSub != null) {
      prevSub!.nextSub = nextSub;
      prevSub = null;
    }

    if (nextSub != null) {
      nextSub!.prevSub = prevSub;
      nextSub = null;
    }

    if (dep.subs == this) {
      dep.subs = prevSub;
    }

    if (dep.subs != null && dep.derived != null) {
      dep.derived!.flags &= ~Flags.tracking;
      Link? link = dep.derived?.deps;
      while (link != null) {
        link.removeSub(true);
      }
    }

    if (sort == false && (--dep.subCounter) == 0 && dep.map != null) {
      dep.map!.remove(dep.key);
    }
  }

  void removeDep() {
    if (prevDep != null) {
      prevDep!.nextDep = nextDep;
      prevDep = null;
    }

    if (nextDep == null) {
      nextDep!.prevDep = prevDep;
      nextDep = null;
    }
  }
}

abstract class Sub {
  Link? deps;
  Link? depsTail;
  Sub? next;
  abstract Flags flags;

  bool notify();

  void prepareDeps() {
    print("prepareDeps called");
    Link? link = deps;
    while (link != null) {
      link.version = -1;
      link.prevActiveLink = link.dep.activeLink;
      link.dep.activeLink = link;
    }
  }

  void cleanupDeps() {
    print("cleanupDeps called");
    Link? head, link = depsTail, tail = link;
    while (link != null) {
      final prev = link.prevDep;
      if (link.version == -1) {
        if (link == tail) {
          tail = prev;
        }

        link.removeSub();
        link.removeDep();
      } else {
        head = link;
      }

      link.dep.activeLink = link.prevActiveLink;
      link.prevActiveLink = null;
      link = prev;
    }

    deps = head;
    depsTail = tail;
  }

  void batch() {
    print("batch called");
    flags |= Flags.notified;
    next = batchedSub;
    batchedSub = this;
  }

  bool get dirty {
    Link? link = deps;

    bool refreshTest() {
      link?.dep.derived?.refresh();
      return link?.version != link?.dep.version;
    }

    while (link != null) {
      if (link.version != link.dep.version || refreshTest()) {
        return true;
      }

      link = link.nextDep;
    }

    return false;
  }
}

class Dep {
  int version = 0;
  Link? activeLink;
  Link? subs;
  Link? subsHead;
  Map<dynamic, Dep>? map;
  Object? key;
  int subCounter = 0;

  final DerivedImpl? derived;

  Dep([this.derived]);

  Link? track() {
    print("Dep.track called. activeSub: $activeSub, shouldTrack: $shouldTrack");
    if (activeSub == null || !shouldTrack || activeSub == derived) {
      print("Dep.track returning null early");
      return null;
    } else if (activeLink == null || activeLink?.sub != activeSub) {
      activeLink = Link(activeSub!, this);

      if (activeSub!.deps != null) {
        activeSub!.deps = activeSub!.depsTail = activeLink;
      } else {
        activeLink!.prevDep = activeSub!.depsTail;
        activeSub!.depsTail!.nextDep = activeLink;
        activeSub!.depsTail = activeLink;
      }

      addSub(activeLink!);
    } else if (activeLink!.version == -1) {
      activeLink!.version = version;
      if (activeLink?.nextDep != null) {
        final next = activeLink!.nextDep!;
        if (activeLink?.prevDep != null) {
          activeLink!.prevDep!.nextDep = next;
        }

        activeLink!.prevDep = activeSub?.depsTail;
        activeLink!.nextDep = null;
        activeSub!.depsTail!.nextDep = activeLink;
        activeSub!.depsTail = activeLink;

        if (activeSub?.deps == activeLink) {
          activeSub!.deps = next;
        }
      }
    }

    return activeLink;
  }

  void trigger() {
    print("Dep.trigger called");
    version++;
    globalVersion++;
    notify();
  }

  void notify() {
    print("Dep.notify called");
    startBatch();
    try {
      Link? link = subs;
      while (link != null) {
        print("Notifying subscriber");
        if (link.sub.notify()) {
          (link.sub as DerivedImpl).dep.notify();
        }
        link = link.nextSub;
      }
    } finally {
      endBatch();
    }
  }

  void addSub(Link link) {
    link.dep.subCounter++;
    if (!link.sub.flags.contains(Flags.tracking)) {
      return;
    }

    final derived = link.dep.derived;
    if (derived != null && link.dep.subs == null) {
      derived.flags |= Flags.tracking | Flags.dirty;
      for (var link = derived.deps; link != null; link = link.nextDep) {
        addSub(link);
      }

      final currentTail = link.dep.subs;
      if (currentTail != link) {
        link.prevSub = currentTail;
        if (currentTail != null) {
          currentTail.nextSub = link;
        }
      }

      link.dep.subs = link;
    }
  }
}

class DerivedImpl<T> extends Sub implements Derived<T> {
  DerivedImpl(this.getter, [this.setter]);

  final T Function(T?) getter;
  final void Function(T)? setter;

  T? _value;

  late final Dep dep = Dep(this);

  @override
  Flags flags = Flags.dirty;
  int version = globalVersion - 1;

  @override
  T get value {
    print("DerivedImpl.value getter called");
    final link = dep.track();
    refresh();

    if (link != null) {
      link.version = dep.version;
    }

    return _value!;
  }

  @override
  set value(T newValue) {
    print("DerivedImpl.value setter called");
    if (setter == null) {
      warn('Write failed: Derived value is readonly.');
      return;
    }

    setter!(newValue);
  }

  @override
  bool notify() {
    print("DerivedImpl.notify called");
    flags |= Flags.dirty;
    if (!flags.contains(Flags.notified) && activeSub != this) {
      batch();
      return true;
    }

    return false;
  }

  void refresh() {
    print("DerivedImpl.refresh called");
    if (flags.contains(Flags.tracking) && !flags.contains(Flags.dirty)) {
      return;
    }

    flags &= ~Flags.dirty;
    if (version == globalVersion) return;

    version = globalVersion;
    flags |= Flags.running;

    final prevSub = activeSub;
    final prevShouldTrack = shouldTrack;

    activeSub = this;
    shouldTrack = true;

    try {
      prepareDeps();
      final value = getter(_value);
      if (dep.version == 0 || hasChanged(value, _value)) {
        _value = value;
        dep.version++;
      }
    } catch (_) {
      dep.version++;
      rethrow;
    } finally {
      activeSub = prevSub;
      shouldTrack = prevShouldTrack;
      cleanupDeps();
      flags &= ~Flags.running;
    }
  }
}

class RefImpl<T> implements Ref<T> {
  RefImpl(this._value) {
    print("RefImpl created with value: $_value");
  }

  T _value;
  late final dep = Dep();

  @override
  T get value {
    print("Getting RefImpl value: $_value");
    dep.track();
    return _value;
  }

  @override
  set value(T newValue) {
    print("Setting RefImpl value from $_value to $newValue");
    final oldValue = _value;
    if (!hasChanged(oldValue, newValue)) {
      print("Value unchanged, not triggering update");
      return;
    }

    _value = newValue;
    print("Triggering dep update");
    dep.trigger();
  }
}

EffectScope? activeEffectScope;

class EffectScope {
  bool active = true;
  bool paused = false;

  final List<ReactiveEffect> effects = [];
  final List<void Function()> cleanups = [];
  final List<EffectScope> scopes = [];

  EffectScope? parent;
  int? index;

  final bool detached;

  EffectScope(this.detached) : parent = activeEffectScope {
    if (!detached && activeEffectScope != null) {
      activeEffectScope!.scopes.add(this);
      index = activeEffectScope!.scopes.length - 1;
    }
  }

  void pause() {
    if (!active) return;
    paused = true;
    for (final scope in scopes) {
      scope.pause();
    }
    for (final effect in effects) {
      effect.pause();
    }
  }

  void resume() {
    if (!active || !paused) return;
    paused = false;
    for (final scope in scopes) {
      scope.resume();
    }
    for (final effect in effects) {
      effect.resume();
    }
  }

  T? run<T>(T Function() runner) {
    if (!active) {
      warn('cannot run an inactive effect scope');
      return null;
    }

    final prevActiveEffectScope = activeEffectScope;
    activeEffectScope = this;

    try {
      return runner();
    } finally {
      activeEffectScope = prevActiveEffectScope;
    }
  }

  void on() {
    if (!detached) {
      warn('This should only be called on non-detached scopes');
    }

    activeEffectScope = this;
  }

  void off() {
    if (!detached) {
      warn('This should only be called on non-detached scopes');
    }

    activeEffectScope = parent;
  }

  void stop([bool fromParent = false]) {
    if (!active) return;
    for (final effect in effects) {
      effect.stop();
    }
    for (final cleanup in cleanups) {
      cleanup();
    }
    for (final scope in scopes) {
      scope.stop();
    }

    if (!detached && parent != null && !fromParent) {
      final last = switch (parent!.scopes) {
        List<EffectScope>(isEmpty: true) => null,
        List<EffectScope> scopes => scopes.removeLast(),
      };
      if (last != null && last != this) {
        parent!.scopes[index!] = last;
        last.index = index;
      }
    }

    parent = null;
    active = false;
  }
}

final pausedQueueEffects = WeakSet<ReactiveEffect>();

class ReactiveEffect<T> extends Sub {
  @override
  Flags flags = Flags.active | Flags.tracking;

  final T Function() runner;

  void Function()? cleanup;
  Function? scheduler;
  void Function()? onStop;

  ReactiveEffect(this.runner) {
    print("ReactiveEffect created");
    if (activeEffectScope?.active == true) {
      activeEffectScope!.effects.add(this);
    }
  }

  @override
  bool notify() {
    print("ReactiveEffect.notify called");
    if (flags.contains(Flags.running) && !flags.contains(Flags.allowRecurse)) {
      print("ReactiveEffect.notify: Already running, not notifying");
      return false;
    }

    if (!flags.contains(Flags.notified)) {
      print("ReactiveEffect.notify: Batching effect");
      batch();
    }

    return false;
  }

  void pause() {
    flags |= Flags.paused;
  }

  void resume() {
    if (!flags.contains(Flags.paused)) return;

    flags &= ~Flags.paused;
    if (pausedQueueEffects.contains(this)) {
      pausedQueueEffects.remove(this);
      trigger();
    }
  }

  T run() {
    print("ReactiveEffect.run started");
    if (!flags.contains(Flags.active)) {
      print("ReactiveEffect.run: Effect not active, just running function");
      return runner();
    }

    flags |= Flags.running;
    cleanupEffect();
    prepareDeps();

    final prevActiveSub = activeSub;
    final prevShouldTrack = shouldTrack;

    print("ReactiveEffect.run: Setting activeSub and shouldTrack");
    activeSub = this;
    shouldTrack = true;

    try {
      print("ReactiveEffect.run: Running effect function");
      return runner();
    } finally {
      print("ReactiveEffect.run: Cleanup and resetting state");
      cleanupDeps();
      activeSub = prevActiveSub;
      shouldTrack = prevShouldTrack;
      flags &= ~Flags.running;
    }
  }

  void stop() {
    if (!flags.contains(Flags.active)) return;

    Link? link = deps;
    while (link != null) {
      link.removeSub();
    }

    deps = depsTail = null;
    cleanupEffect();
    onStop?.call();
    flags &= ~Flags.active;
  }

  void trigger() {
    if (flags.contains(Flags.paused)) {
      pausedQueueEffects.add(this);
      return;
    } else if (scheduler != null) {
      Function.apply(scheduler!, []);
      return;
    }

    runIfDirty();
  }

  void cleanupEffect() {
    final cleanup = this.cleanup;
    if (this.cleanup == null) return;

    final prevActiveSub = activeSub;
    activeSub = null;

    try {
      cleanup!();
    } finally {
      activeSub = prevActiveSub;
    }
  }

  void runIfDirty() {
    if (dirty) {
      run();
    }
  }
}

void effect<T>(T Function() runner) {
  print("effect function called");
  final inner = ReactiveEffect(runner);

  try {
    print("Running effect for the first time");
    inner.run();
  } catch (e) {
    print("Error in effect: $e");
    inner.stop();
    rethrow;
  }

  print("Effect setup complete");
}

void main() {
  print("Starting main function");
  final a = RefImpl(1);
  print("Created RefImpl a with initial value 1");

  print("Setting up effect");
  effect(() {
    print("Effect function running");
    print("Current value of a: ${a.value}");
  });

  print("Changing value of a");
  a.value = 2;

  print("Main function complete");
}
