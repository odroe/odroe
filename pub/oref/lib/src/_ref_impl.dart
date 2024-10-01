import '_dependent.dart';
import '_global.dart';
import '_utils.dart';
import 'types.dart';

class RefImpl<T> implements Ref<T> {
  RefImpl(this.innerValue);

  T innerValue;
  bool dirty = true;

  late final List<Dependent> dependents = [];

  @override
  T get value {
    if (evalElement != null && dirty) {}

    return innerValue;
  }

  @override
  set value(T newValue) {
    if (!hasChanged(innerValue, newValue)) return;

    innerValue = newValue;
    dirty = true;

    trigger();
  }

  void track() {
    if (evalElement == null || !dirty) return;
    dirty = false;
  }

  void trigger() {
    if (!dirty) return;
    dependents.trigger();
  }
}
