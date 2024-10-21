import '../../types/private.dart' as private;
import '../batch.dart' as impl;
import '../reactive.dart' as impl;
import '../ref.dart' as impl;

final class ReactiveIterable<E> extends BaseReactiveIterable<E, Iterable<E>> {
  ReactiveIterable(super.raw);
}

abstract base class BaseReactiveIterable<E, T extends Iterable<E>>
    extends impl.BaseRef<T> implements private.Reactive<T>, Iterable<E> {
  BaseReactiveIterable(super.raw);

  @override
  bool any(bool Function(E element) test) {
    return value.any(test);
  }

  @override
  Iterable<R> cast<R>() {
    return Iterable.castFrom(this);
  }

  @override
  bool contains(Object? element) {
    return raw.contains(impl.toRaw(element));
  }

  @override
  E elementAt(int index) => value.elementAt(index);

  @override
  bool every(bool Function(E element) test) {
    return value.every(test);
  }

  @override
  Iterable<R> expand<R>(Iterable<R> Function(E element) toElements) {
    return value.expand(toElements);
  }

  @override
  E get first => value.first;

  @override
  E firstWhere(bool Function(E element) test, {E Function()? orElse}) {
    return value.firstWhere(test, orElse: orElse);
  }

  @override
  R fold<R>(R initialValue, R Function(R previousValue, E element) combine) {
    return value.fold(initialValue, combine);
  }

  @override
  Iterable<E> followedBy(Iterable<E> other) {
    return value.followedBy(other);
  }

  @override
  @Deprecated('Try using for loop.')
  void forEach(void Function(E element) action) {
    dep.track();
    impl.startBatch();
    for (final element in raw) {
      action(element);
    }
    impl.endBatch();
  }

  @override
  bool get isEmpty => value.isEmpty;

  @override
  bool get isNotEmpty => value.isNotEmpty;

  @override
  Iterator<E> get iterator => value.iterator;

  @override
  String join([String separator = ""]) => value.join(separator);

  @override
  E get last => value.last;

  @override
  E lastWhere(bool Function(E element) test, {E Function()? orElse}) {
    return value.lastWhere(test, orElse: orElse);
  }

  @override
  int get length => value.length;

  @override
  Iterable<R> map<R>(R Function(E e) toElement) {
    return value.map(toElement);
  }

  @override
  E reduce(E Function(E value, E element) combine) {
    return value.reduce(combine);
  }

  @override
  E get single => value.single;

  @override
  E singleWhere(bool Function(E element) test, {E Function()? orElse}) {
    return value.singleWhere(test, orElse: orElse);
  }

  @override
  Iterable<E> skip(int count) {
    return value.skip(count);
  }

  @override
  Iterable<E> skipWhile(bool Function(E value) test) {
    return value.skipWhile(test);
  }

  @override
  Iterable<E> take(int count) {
    return value.take(count);
  }

  @override
  Iterable<E> takeWhile(bool Function(E value) test) {
    return value.takeWhile(test);
  }

  @override
  List<E> toList({bool growable = true}) {
    return value.toList(growable: growable);
  }

  @override
  Set<E> toSet() {
    return value.toSet();
  }

  @override
  Iterable<E> where(bool Function(E element) test) {
    return value.where(test);
  }

  @override
  Iterable<R> whereType<R>() {
    return value.whereType<R>();
  }
}
