import 'batch.dart';
import 'corss_link.dart';
import 'dependency.dart';
import 'effect.dart';
import 'flags.dart';
import 'global_version.dart';
import 'ref.dart';
import 'subscriber.dart';
import 'warn.dart';

abstract interface class ComputedRef<T> implements Ref<T> {}

final class ComputedImpl<T> implements ComputedRef<T>, Subscriber {
  ComputedImpl._(this.getter, [this.setter])
      : version = -1,
        flags = Flags.dirty;

  late final dep = Dependency(this);
  final T Function(T? oldValue) getter;
  final void Function(T newValue)? setter;

  T? raw;

  @override
  Subscriber? next;

  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  int version;

  @override
  int flags;

  @override
  void notify() {
    flags |= Flags.dirty;
    if (flags & Flags.notified == 0 && activeSub != this) {
      addBatchSub(this);
    }
  }

  @override
  T get value {
    final link = dep.track();
    refreshComputed(this);
    if (link != null) {
      link.version = dep.version;
    }

    return raw!;
  }

  set value(T value) {
    setter?.call(value);
    if (setter == null) {
      warn('Write operation failed: computed value is readonly');
    }
  }
}

void refreshComputed(ComputedImpl computed) {
  if (computed.flags & Flags.tracking != 0 &&
      computed.flags & Flags.dirty == 0) {
    return;
  }

  computed.flags &= ~Flags.dirty;
  if (computed.version == globalVersion) {
    return;
  }

  computed.version = globalVersion;
  computed.flags |= Flags.running;

  if (computed.dep.version > 0 &&
      computed.depsHead != null &&
      !isDirty(computed)) {
    return;
  }

  final resetActiveSub = setActiveSub(computed);
  enableTracking();

  try {
    prepareDeps(computed);
    final value = computed.getter(computed.raw);
    if (computed.dep.version == 0 || !identical(computed.raw, value)) {
      computed.raw = value;
      computed.dep.version++;
    }
  } catch (e) {
    computed.dep.version++;
  } finally {
    resetActiveSub();
    resetTracking();
    cleanupDeps(computed);
    computed.flags &= ~Flags.running;
  }
}
