import '../types.dart';

final class CustomRef<T> implements WritableRef<T> {
  const CustomRef(this.getter, this.setter);

  final T Function() getter;
  final void Function(T) setter;

  @override
  T get value => getter();

  @override
  set value(T value) => setter(value);
}
