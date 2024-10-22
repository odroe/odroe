import 'global.dart';

enum Lifecycle {
  beforeMount,
  beforeUpdate,
  beforeUnmount,
  mounted,
  updated,
  unmounted,
  activated,
  deactivated,
}

abstract interface class LifecycleHooks {
  factory LifecycleHooks() = _LifecycleHooksImpl;

  void register<T extends Function>(Lifecycle lifecycle, T hook,
      {bool prepend = false});

  Iterable<T> lookup<T extends Function>(Lifecycle lifecycle);

  void call<T extends Function>(Lifecycle lifecycle,
      {List<dynamic>? positionalArguments,
      Map<Symbol, dynamic>? namedArguments});
}

final class _LifecycleHooksImpl implements LifecycleHooks {
  final hooksStore = <Lifecycle, List<Function>>{};

  @override
  Iterable<T> lookup<T extends Function>(Lifecycle lifecycle) sync* {
    final hooks = hooksStore[lifecycle]?.cast<T>();
    if (hooks != null) {
      yield* hooks;
    }
  }

  @override
  void register<T extends Function>(Lifecycle lifecycle, T hook,
      {bool prepend = false}) {
    final hooks = hooksStore[lifecycle] ??= [];

    if (prepend) {
      return hooks.insert(0, hook);
    }

    hooks.add(hook);
  }

  @override
  void call<T extends Function>(
    Lifecycle lifecycle, {
    List<dynamic>? positionalArguments,
    Map<Symbol, dynamic>? namedArguments,
  }) {
    for (final hook in lookup<T>(lifecycle)) {
      Function.apply(hook, positionalArguments, namedArguments);
    }
  }
}

void _registerHook<T extends Function>(Lifecycle lifecycle, T hook) {
  currentElement?.lifecycleHooks.register(lifecycle, hook);
}

void onBeforeMount(void Function() hook) {
  _registerHook(Lifecycle.beforeMount, hook);
}

void onBeforeUpdate(void Function() hook) {
  _registerHook(Lifecycle.beforeUpdate, hook);
}

void onBeforeUnmount(void Function() hook) {
  _registerHook(Lifecycle.beforeUnmount, hook);
}

void onMounted(void Function() hook) {
  _registerHook(Lifecycle.mounted, hook);
}

void onUpdated(void Function() hook) {
  _registerHook(Lifecycle.updated, hook);
}

void onUnmounted(void Function() hook) {
  _registerHook(Lifecycle.unmounted, hook);
}

void onActivated(void Function() hook) {
  _registerHook(Lifecycle.activated, hook);
}

void onDeactivated(void Function() hook) {
  _registerHook(Lifecycle.deactivated, hook);
}
