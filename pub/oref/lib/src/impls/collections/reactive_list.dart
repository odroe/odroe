import '../../types/private.dart' as private;
import '../reactive.dart' as impl;

class ReactiveList<E> implements private.Reactive<List<E>>, List<E> {
  ReactiveList(this.raw, this.dep, this.shallow);

  late final Map<int, E> targets = {};

  @override
  List<E> raw;

  @override
  List<E> get value {
    dep.track();
    return this;
  }

  @override
  set value(List<E> newValue) {
    raw = impl.toRaw(newValue);
    dep.trigger();
  }

  @override
  final private.Dep dep;

  @override
  final bool shallow;

  @override
  E get first {
    final element = raw.first;
    dep.track();

    if (!shallow && impl.isCollection(element)) {
      return targets[0] ??= impl.createReactive(element, dep, shallow);
    }

    return element;
  }

  @override
  set first(E element) {
    final oldElement = raw.first;
    final newElement = impl.toRaw(element);

    if (identical(oldElement, newElement)) {
      return;
    }

    raw.first = newElement;
    targets.remove(0);

    dep.trigger();
  }

  @override
  E get last {
    final element = raw.last;
    dep.track();

    if (!shallow && impl.isCollection(element)) {
      return targets[raw.length - 1] ??=
          impl.createReactive(element, dep, shallow);
    }

    return element;
  }

  @override
  set last(E value) {
    final oldElement = raw.first;
    final newElement = impl.toRaw(value);

    if (identical(oldElement, newElement)) {
      return;
    }

    raw.last = newElement;
    targets.remove(raw.length - 1);

    dep.trigger();
  }

  @override
  int get length {
    dep.track();
    return raw.length;
  }

  @override
  set length(int length) {
    raw.length = length;
    targets.removeWhere((key, _) => key > length);
    dep.track();
  }

  @override
  List<E> operator +(List<E> other) {
    dep.track();
    return raw + other;
  }

  @override
  E operator [](int index) {
    final element = raw[index];
    if (!shallow && impl.isCollection(element)) {
      return targets[index] ??= impl.createReactive(element, dep, shallow);
    }

    return element;
  }

  @override
  void operator []=(int index, E value) {
    final oldValue = raw[index];
    final newValue = impl.toRaw(value);

    if (identical(oldValue, newValue)) {
      return;
    }

    targets.remove(index);
    raw[index] = impl.toRaw(newValue);
    dep.trigger();
  }

  @override
  void add(E value) {
    raw.add(impl.toRaw(value));
    dep.trigger();
  }

  @override
  void addAll(Iterable<E> iterable) {
    raw.addAll(iterable.map((e) => impl.toRaw(e)));
    dep.trigger();
  }

  @override
  bool any(bool Function(E element) test) {
    dep.track();
    return raw.any(test);
  }

  @override
  Map<int, E> asMap() {
    dep.track();

    return raw.asMap().map((index, value) {
      if (!shallow && impl.isCollection(value)) {
        return MapEntry(
          index,
          targets[index] ??= impl.createReactive(value, dep, shallow),
        );
      }

      return MapEntry(index, value);
    });
  }

  @override
  List<R> cast<R>() => List.castFrom(this);

  @override
  void clear() {
    raw.clear();
    targets.clear();
    dep.trigger();
  }

  @override
  bool contains(Object? element) {
    dep.track();

    return raw.contains(element);
  }

  @override
  E elementAt(int index) {
    dep.track();
    final element = raw.elementAt(index);
    if (!shallow && impl.isCollection(element)) {
      return targets[index] ??= impl.createReactive(element, dep, shallow);
    }

    return element;
  }

  @override
  bool every(bool Function(E element) test) {
    dep.track();
    return raw.every((e) => test(impl.toRaw(e)));
  }

  @override
  Iterable<T> expand<T>(Iterable<T> Function(E element) toElements) {
    dep.track();

    return raw.expand((e) => toElements(impl.toRaw(e)));
  }

  @override
  void fillRange(int start, int end, [E? fillValue]) {
    raw.fillRange(start, end, impl.toRaw(fillValue));
    dep.trigger();
  }

  @override
  E firstWhere(bool Function(E element) test, {E Function()? orElse}) {
    dep.track();
    return raw.firstWhere((e) => test(impl.toRaw(e)), orElse: orElse);
  }

  @override
  T fold<T>(T initialValue, T Function(T previousValue, E element) combine) {
    dep.track();
    return raw.fold(initialValue, (prev, e) => combine(prev, impl.toRaw(e)));
  }

  @override
  Iterable<E> followedBy(Iterable<E> other) {
    dep.track();
    return raw.followedBy(other);
  }

  @override
  @Deprecated('Try using for loop.')
  void forEach(void Function(E element) action) {
    dep.track();
    for (var element in raw) {
      action(impl.toRaw(element));
    }
  }

  @override
  Iterable<E> getRange(int start, int end) {
    dep.track();

    return raw.getRange(start, end).map((e) => impl.toRaw(e));
  }

  @override
  int indexOf(E element, [int start = 0]) {
    dep.track();
    return raw.indexOf(element, start);
  }

  @override
  int indexWhere(bool Function(E element) test, [int start = 0]) {
    dep.track();
    return raw.indexWhere((element) => test(impl.toRaw(element)), start);
  }

  @override
  void insert(int index, E element) {
    raw.insert(index, impl.toRaw(element));
    targets.remove(index);
    dep.trigger();
  }

  @override
  void insertAll(int index, Iterable<E> iterable) {
    raw.insertAll(index, impl.toRaw(iterable));
    targets.removeWhere((key, _) => key >= index);
    dep.trigger();
  }

  @override
  bool get isEmpty {
    dep.track();
    return raw.isEmpty;
  }

  @override
  bool get isNotEmpty {
    dep.track();
    return raw.isNotEmpty;
  }

  @override
  Iterator<E> get iterator => throw UnimplementedError();

  @override
  String join([String separator = ""]) {
    // TODO: implement join
    throw UnimplementedError();
  }

  @override
  int lastIndexOf(E element, [int? start]) {
    // TODO: implement lastIndexOf
    throw UnimplementedError();
  }

  @override
  int lastIndexWhere(bool Function(E element) test, [int? start]) {
    // TODO: implement lastIndexWhere
    throw UnimplementedError();
  }

  @override
  E lastWhere(bool Function(E element) test, {E Function()? orElse}) {
    // TODO: implement lastWhere
    throw UnimplementedError();
  }

  @override
  Iterable<T> map<T>(T Function(E e) toElement) {
    // TODO: implement map
    throw UnimplementedError();
  }

  @override
  E reduce(E Function(E value, E element) combine) {
    // TODO: implement reduce
    throw UnimplementedError();
  }

  @override
  bool remove(Object? value) {
    // TODO: implement remove
    throw UnimplementedError();
  }

  @override
  E removeAt(int index) {
    // TODO: implement removeAt
    throw UnimplementedError();
  }

  @override
  E removeLast() {
    // TODO: implement removeLast
    throw UnimplementedError();
  }

  @override
  void removeRange(int start, int end) {
    // TODO: implement removeRange
  }

  @override
  void removeWhere(bool Function(E element) test) {
    // TODO: implement removeWhere
  }

  @override
  void replaceRange(int start, int end, Iterable<E> replacements) {
    // TODO: implement replaceRange
  }

  @override
  void retainWhere(bool Function(E element) test) {
    // TODO: implement retainWhere
  }

  @override
  // TODO: implement reversed
  Iterable<E> get reversed => throw UnimplementedError();

  @override
  void setAll(int index, Iterable<E> iterable) {
    // TODO: implement setAll
  }

  @override
  void setRange(int start, int end, Iterable<E> iterable, [int skipCount = 0]) {
    // TODO: implement setRange
  }

  @override
  void shuffle([Random? random]) {
    // TODO: implement shuffle
  }

  @override
  // TODO: implement single
  E get single => throw UnimplementedError();

  @override
  E singleWhere(bool Function(E element) test, {E Function()? orElse}) {
    // TODO: implement singleWhere
    throw UnimplementedError();
  }

  @override
  Iterable<E> skip(int count) {
    // TODO: implement skip
    throw UnimplementedError();
  }

  @override
  Iterable<E> skipWhile(bool Function(E value) test) {
    // TODO: implement skipWhile
    throw UnimplementedError();
  }

  @override
  void sort([int Function(E a, E b)? compare]) {
    // TODO: implement sort
  }

  @override
  List<E> sublist(int start, [int? end]) {
    // TODO: implement sublist
    throw UnimplementedError();
  }

  @override
  Iterable<E> take(int count) {
    // TODO: implement take
    throw UnimplementedError();
  }

  @override
  Iterable<E> takeWhile(bool Function(E value) test) {
    // TODO: implement takeWhile
    throw UnimplementedError();
  }

  @override
  List<E> toList({bool growable = true}) {
    // TODO: implement toList
    throw UnimplementedError();
  }

  @override
  Set<E> toSet() {
    // TODO: implement toSet
    throw UnimplementedError();
  }

  @override
  Iterable<E> where(bool Function(E element) test) {
    // TODO: implement where
    throw UnimplementedError();
  }

  @override
  Iterable<T> whereType<T>() {
    // TODO: implement whereType
    throw UnimplementedError();
  }
}
