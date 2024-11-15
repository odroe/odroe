import '../warn.dart';
import 'batch.dart';
import 'corss_link.dart';
import 'dependency.dart';
import 'flags.dart';
import 'subscriber.dart';
import 'types.dart';
import 'utils.dart';

final class ComputedRefImpl<T> implements ComputedRef<T>, Subscriber {
  ComputedRefImpl(this.getter, [this.setter])
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

  @override
  set value(T value) {
    setter?.call(value);
    if (setter == null) {
      warn('Write operation failed: computed value is readonly');
    }
  }
}
