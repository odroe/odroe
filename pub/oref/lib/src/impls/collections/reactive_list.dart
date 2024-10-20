import 'dart:math';

import '../../types/private.dart' as private;
import 'reactive_iterable.dart' as impl;

class ReactiveList<E> extends impl.ReactiveIterable<E, List<E>>
    implements private.Reactive<List<E>>, List<E> {
  ReactiveList(super.raw);

  @override
  List<E> operator +(List<E> other) {
    return value + other;
  }

  @override
  E operator [](int index) => value[index];

  @override
  void operator []=(int index, E value) {
    final prev = raw[index];
    if (identical(prev, value)) {
      return;
    }

    dep.trigger();
  }

  @override
  void add(E value) {
    raw.add(value);
    dep.trigger();
  }

  @override
  void addAll(Iterable<E> iterable) {
    raw.addAll(iterable);
    dep.trigger();
  }

  @override
  Map<int, E> asMap() => value.asMap();

  @override
  List<R> cast<R>() {
    return value.cast<R>();
  }

  @override
  void clear() {
    raw.clear();
    dep.trigger();
  }

  @override
  void fillRange(int start, int end, [E? fillValue]) {
    raw.fillRange(start, end, fillValue);
    dep.trigger();
  }

  @override
  set first(E value) {
    final prev = raw.first;
    raw.first = value;

    if (!identical(prev, value)) {
      dep.trigger();
    }
  }

  @override
  Iterable<E> getRange(int start, int end) {
    return value.getRange(start, end);
  }

  @override
  int indexOf(E element, [int start = 0]) {
    return value.indexOf(element, start);
  }

  @override
  int indexWhere(bool Function(E element) test, [int start = 0]) {
    return value.indexWhere(test, start);
  }

  @override
  void insert(int index, E element) {
    raw.insert(index, element);
    dep.trigger();
  }

  @override
  void insertAll(int index, Iterable<E> iterable) {
    raw.insertAll(index, iterable);
    dep.trigger();
  }

  @override
  set last(E value) {
    final prev = raw.last;
    raw.last = value;

    if (!identical(prev, value)) {
      dep.trigger();
    }
  }

  @override
  int lastIndexOf(E element, [int? start]) {
    return value.lastIndexOf(element, start);
  }

  @override
  int lastIndexWhere(bool Function(E element) test, [int? start]) {
    return value.lastIndexWhere(test, start);
  }

  @override
  set length(int newLength) {
    final prevLength = raw.length;
    raw.length = newLength;

    if (prevLength != newLength) {
      dep.trigger();
    }
  }

  @override
  bool remove(Object? value) {
    if (remove(value)) {
      dep.trigger();
      return true;
    }

    return false;
  }

  @override
  E removeAt(int index) {
    try {
      return raw.removeAt(index);
    } finally {
      dep.trigger();
    }
  }

  @override
  E removeLast() {
    try {
      return raw.removeLast();
    } finally {
      dep.trigger();
    }
  }

  @override
  void removeRange(int start, int end) {
    raw.removeRange(start, end);
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

    if (markNeedTrigger) {
      dep.trigger();
    }
  }

  @override
  void replaceRange(int start, int end, Iterable<E> replacements) {
    raw.replaceRange(start, end, replacements);
    if (replacements.isNotEmpty) {
      dep.trigger();
    }
  }

  @override
  void retainWhere(bool Function(E element) test) {
    bool makrNeedTrigger = false;
    raw.retainWhere((element) {
      if (test(element)) {
        return true;
      }

      makrNeedTrigger = true;
      return false;
    });

    if (makrNeedTrigger) dep.trigger();
  }

  @override
  Iterable<E> get reversed => value.reversed;

  @override
  void setAll(int index, Iterable<E> iterable) {
    raw.setAll(index, iterable);
    dep.trigger();
  }

  @override
  void setRange(int start, int end, Iterable<E> iterable, [int skipCount = 0]) {
    raw.setRange(start, end, iterable, skipCount);
    dep.trigger();
  }

  @override
  void shuffle([Random? random]) {
    raw.shuffle(random);
    dep.trigger();
  }

  @override
  void sort([int Function(E a, E b)? compare]) {
    raw.sort(compare);
    dep.trigger();
  }

  @override
  List<E> sublist(int start, [int? end]) {
    return value.sublist(start, end);
  }
}
