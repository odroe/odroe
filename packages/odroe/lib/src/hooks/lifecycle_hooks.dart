import '../element.dart';

enum LifecycleType {
  onMounted,
  onUpdated,
  onUnmounted,
  onBeforeUpdate,
  onBeforeUnmount,
  onActivated,
  onDeactivated,
}

final class Lifecycle {
  const Lifecycle(this.type, void Function() callback) : _callback = callback;

  final LifecycleType type;
  final void Function() _callback;

  void call() => _callback();
}

void _define(LifecycleType type, void Function() callback) {
  final element = getCurrentElement();
  final lifecycle = Lifecycle(type, callback);

  element.lifecycle.add(lifecycle);
}

void onMounted(void Function() callback) =>
    _define(LifecycleType.onMounted, callback);
void onUnmounted(void Function() callback) =>
    _define(LifecycleType.onUnmounted, callback);
void onUpdated(void Function() callback) =>
    _define(LifecycleType.onUpdated, callback);
void onBeforeUnmount(void Function() callback) =>
    _define(LifecycleType.onBeforeUnmount, callback);
void onBeforeUpdate(void Function() callback) =>
    _define(LifecycleType.onBeforeUpdate, callback);
void onActivated(void Function() callback) =>
    _define(LifecycleType.onActivated, callback);
void onDeactivated(void Function() callback) =>
    _define(LifecycleType.onDeactivated, callback);
