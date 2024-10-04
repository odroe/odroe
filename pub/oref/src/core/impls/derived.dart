import '../types/private.dart' as private;
import 'batch.dart' as impl;
import 'dep.dart' as impl;
import 'sub.dart' as impl;
import 'flags.dart';
import 'global.dart';
import 'utils.dart';

class Derived<T> implements private.Derived<T> {
  Derived(this.getter, [this.setter]);

  final T Function() getter;
  final void Function(T)? setter;

  @override
  int version = globalVersion - 1;

  @override
  private.Link? deps;

  @override
  private.Link? depsTail;

  @override
  int flags = Flags.dirty;

  @override
  private.Sub? next;

  @override
  late final private.Dep dep = impl.Dep(this);

  dynamic _value;

  @override
  T get value {
    final link = dep.track();

    // Refresh the derived value if it's dirty
    refreshDerived(this);

    // Sync version after evaluation.
    if (link != null) {
      link.version = dep.version;
    }

    return _value;
  }

  @override
  set value(T newValue) {
    setter?.call(newValue);
    if (setter == null) {
      warn('Derived value is readonly');
    }
  }

  @override
  Derived<T>? notify() {
    flags |= Flags.dirty;
    if ((flags & Flags.notified) == 0 && activeSub != this) {
      impl.batch(this);

      return this;
    } else if (dev) {
      warn('Derived.notify() called on an already notified derived');
    }

    return null;
  }
}

void refreshDerived<T>(Derived<T> derived) {
  if ((derived.flags & Flags.tracking) != 0 &&
      (derived.flags & Flags.dirty) == 0) {
    return;
  }

  derived.flags &= ~Flags.dirty;

  // If version is the same, it means the derived value is already up to date.
  if (derived.version == globalVersion) {
    return;
  }

  derived.version = globalVersion;
  derived.flags |= Flags.running;

  final dep = derived.dep;
  final prevSub = activeSub;
  final prevShouldTrack = shouldTrack;

  activeSub = derived;
  shouldTrack = true;

  try {
    impl.prepareDeps(derived);
    final value = derived.getter();
    if (dep.version == 0 || hasChanged(derived._value, value)) {
      derived._value = value;
      dep.version++;
    }
  } catch (_) {
    dep.version++;
    rethrow;
  } finally {
    activeSub = prevSub;
    shouldTrack = prevShouldTrack;
    impl.cleanupDeps(derived);
    derived.flags &= ~Flags.running;
  }
}