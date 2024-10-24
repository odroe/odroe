import '../../types/private.dart' as private;
import 'reactive_iterable.dart' as impl;

final class ReactiveSet<E> extends impl.BaseReactiveIterable<E, Set<E>>
    implements Set<E>, private.Reactive<Set<E>> {
  ReactiveSet(super.raw);

  @override
  Set<R> cast<R>() {
    return value.cast<R>();
  }

  @override
  bool add(E value) {
    if (raw.add(value)) {
      dep.trigger();
      return true;
    }

    return false;
  }

  @override
  void addAll(Iterable<E> elements) {
    raw.addAll(elements);
    dep.trigger();
  }

  @override
  void clear() {
    raw.clear();
    dep.trigger();
  }

  @override
  bool containsAll(Iterable<Object?> other) {
    return value.containsAll(other);
  }

  @override
  Set<E> difference(Set<Object?> other) {
    return value.difference(other);
  }

  @override
  Set<E> intersection(Set<Object?> other) {
    return value.intersection(other);
  }

  @override
  E? lookup(Object? object) {
    return value.lookup(object);
  }

  @override
  bool remove(Object? value) {
    if (raw.remove(value)) {
      dep.trigger();
      return true;
    }

    return false;
  }

  @override
  void removeAll(Iterable<Object?> elements) {
    raw.removeAll(elements);
    dep.trigger();
  }

  @override
  void removeWhere(bool Function(E element) test) {
    bool markNeedTrigger = false;
    raw.removeWhere((element) {
      if (test(element)) {
        return markNeedTrigger = true;
      }
      return false;
    });

    if (markNeedTrigger) dep.trigger();
  }

  @override
  void retainAll(Iterable<Object?> elements) {
    raw.retainAll(elements);
    dep.trigger();
  }

  @override
  void retainWhere(bool Function(E element) test) {
    bool makrNeedTrigger = false;
    raw.retainWhere((element) {
      if (test(element)) return true;
      makrNeedTrigger = true;
      return false;
    });

    if (makrNeedTrigger) dep.trigger();
  }

  @override
  Set<E> union(Set<E> other) {
    return value.union(other);
  }
}
