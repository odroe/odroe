import 'corss_link.dart';
import 'debugger.dart';
import 'dependency.dart';
import 'effect.dart';
import 'flags.dart';
import 'global_version.dart';
import 'ref.dart';
import 'subscriber.dart';

abstract interface class ComputedRef<T> implements Ref<T> {}

final class ComputedImpl<T> implements ComputedRef<T>, Subscriber {
  final Dependency dep;
  final T Function() fn;

  T? raw;

  @override
  T get value => throw UnimplementedError();

  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  int version;

  @override
  int flags;

  @override
  Subscriber? next;

  @override
  void notify() {
    // TODO: implement notify
  }

  @override
  void Function(DebuggerEvent event)? onTrack;

  @override
  void Function(DebuggerEvent event)? onTrigger;
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
    final value = computed.fn();
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
