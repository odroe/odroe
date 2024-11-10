import '../types.dart';
import 'dependency.dart';

final class WritableRefImpl<T> implements WritableRef<T> {
  WritableRefImpl(this.raw);

  T raw;
  late final dep = Dependency();

  @override
  T get value {
    dep.track();
    return raw;
  }

  @override
  set value(T value) {
    if (identical(raw, value)) return;
    raw = value;
    dep.trigger();
  }
}
