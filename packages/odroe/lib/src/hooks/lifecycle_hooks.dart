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

/// Registers a callback to be called after the Setup-widget has been mounted.
void onMounted(void Function() callback) =>
    _define(LifecycleType.onMounted, callback);

/// Registers a callback to be called after the Setup-widget has been unmounted.
void onUnmounted(void Function() callback) =>
    _define(LifecycleType.onUnmounted, callback);

/// Registers a callback to be called after the Setup-widget has updated its element tree due to a signals/props change.
void onUpdated(void Function() callback) =>
    _define(LifecycleType.onUpdated, callback);

/// Registers a hook to be called right before a Setup-widget is to be unmounted.
void onBeforeUnmount(void Function() callback) =>
    _define(LifecycleType.onBeforeUnmount, callback);

/// Registers a hook to be called right before the Setup-widget is about to update its element tree due to a signals/props change.
void onBeforeUpdate(void Function() callback) =>
    _define(LifecycleType.onBeforeUpdate, callback);

/// Registers a callback to be called after the Setup-widget is inserted into the element as part of a tree cached by keep alive.
void onActivated(void Function() callback) =>
    _define(LifecycleType.onActivated, callback);

/// Registers a callback to be called after the Setup-widget is removed from the element as part of a tree cached by keep alive.
void onDeactivated(void Function() callback) =>
    _define(LifecycleType.onDeactivated, callback);
