---
title: Documentation → Oref - Core API
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Oref - Core API
---

Oref Core API

## Reference (`ref()`)

Accepts an internal value and returns a reactive, mutable `Ref<T>` object, which has only one property `.value` pointing to its internal value.

- Type:
  ::: code-group
  ```dart [Dart]
  Ref<T> ref<T>(T value);
  ```
  ```dart [Flutter]
  Ref<T> ref<T>(BuildContext context, T value);
  ```
  :::
- Return Type:
  ```dart
  abstract interface class Ref<T> {
      T value;
  }
  ```
- Details

  The `Ref<T>` object is mutable, which means we can assign new values using `.value`. It is also reactive, meaning all operations that read `.value` will be tracked, and assignment operations will trigger related side effects.

- Example:
  ```dart
  final count = ref(0);
  print(count.value); // 0

  count.value = 1;
  print(count.value); // 1
  ```

## Derived (`derived()`)

`derived()` accepts a getter function (type: `T Function()`) and returns a read-only reactive `Derived<T>` object. This `Derived<T>` exposes the return value of the getter function through `.value`.

- Type:
  ::: code-group
  ```dart [Dart]
  Derived<T> derived<T>(T Function() getter);
  ```
  ```dart [Flutter]
  Derived<T> derived<T>(BuildContext context, T Function() getter);
  ```
  :::
- Return Type:
  ```dart
  abstract interface class Derived<T> extends Ref<T> {
      T get value;
  }
  ```
- Example:
  ::: code-group
  ```dart [Dart]
  final count = ref(1);
  final plusOne = derived(() => count.value + 1);

  print(plusOne.value); // 2

  plusOne.value++; // Invalid, outputs warning in DevTools console under Dart VM
  ```
  ```dart [Flutter]
  final count = ref(context, 1);
  final plusOne = derived(context, () => count.value + 1);

  print(plusOne.value); // 2

  plusOne.value++; // Invalid, outputs warning in DevTools console in Flutter dev mode
  ```
  :::

### Valuable Derived (`derived.valuable()`)

Sometimes when implementing derivation, we need to use the previous value in the calculation. In such cases, we need `derived.valuable`:

::: code-group
```dart [Dart]
final count = ref(0);
final total = derived.valuable<int>(
    (prev) => count.value + (prev ?? 0)
);

print(total.value); // 0

count.value = 10;
print(total.value); // 10

count.value = 20;
print(total.value); // 30
```
```dart [Flutter]
final count = ref(context, 0);
final total = derived.valuable<int>(
    context,
    (prev) => count.value + (prev ?? 0)
);

print(total.value); // 0

count.value = 10;
print(total.value); // 10

count.value = 20;
print(total.value); // 30
```
:::

### Writable Derived (`derived.writable()`)

Writable derived allows you to implement reverse calculation-like functionality. We need to use the `derived.writable()` function:

::: code-group
```dart [Dart]
final count = ref(0);
final doubleCount = derived.writable<int>(
    (_) => count.value * 2, // multiply count by 2
    (value) => count.value = value ~/ 2, // reverse calculation, inverse operation on count
);

doubleCount.value = 10;
print(count.value); // 5

count.value = 10;
print(doubleCount.value); // 20
```
```dart [Flutter]
final count = ref(context, 0);
final doubleCount = derived.writable<int>(
    context,
    (_) => count.value * 2, // multiply count by 2
    (value) => count.value = value ~/ 2, // reverse calculation, inverse operation on count
);

doubleCount.value = 10;
print(count.value); // 5

count.value = 10;
print(doubleCount.value); // 20
```
:::

Thus, we can directly implement reversible reactive data operations on top of derived reactivity.

## Side Effect (`effect()`)

Immediately runs a function while reactively tracking the reactive data used within the function as dependencies, and re-executes the function when the tracked dependencies change:

- Type:
  ::: code-group
  ```dart [Dart]
  EffectRunner<T> effect<T>(
      T Function() runner, {
      void Function()? scheduler,
      void Function()? onStop,
  });
  ```
  ```dart [Flutter]
  EffectRunner<T> effect<T>(
      BuildContext context,
      T Function() runner, {
      void Function()? scheduler,
      void Function()? onStop,
  });
  ```
  :::
- Return Type:
  ```dart
  abstract interface class EffectRunner<T> {
      Effect<T> get effect;
      T call();
  }

  abstract interface class Effect<T> {
      void stop();
      void pause();
      void resume();
  }
  ```
  > Click "[Effect\<T\> class API](https://pub.dev/documentation/oref/latest/oref/Effect-class.html)" for more information
- Details:
  - `context`: Context of Flutter Widget. <Badge type="tip" text="Flutter" />
  - `runner`: The side effect function to be executed.
  - `scheduler`: Custom side effect trigger
  - `onStop`: Executed when the side effect is stopped.
- Example:
  ::: code-group
  ```dart [Dart]
  final count = ref(0);

  effect(() => print(count.value));
  // -> Prints 0

  count.value++;
  // -> Prints 1
  ```

  ```dart [Flutter]
  final count = ref(context, 0);

  effect(context, () => print(count.value));
  // -> Prints 0

  count.value++;
  // -> Prints 1
  ```
  :::

### Side Effect Cleanup

Sometimes, before re-running the side effect function, we run another function to clean up previous resources:

::: code-group
```dart [Dart]
final tick = ref(0);
final duration = ref(const Duration(seconds: 1))

effect(() {
    // Listen to duration.value and create an internal Timer.
    final timer = Timer.periodic(duration.value, (timer) {
        tick.value = timer.tick;
    });

    // Stop the previous Timer before duration updates.
    onEffectCleanup(() {
        if (timer.isActive) timer.cancel();
    });
});
```
```dart [Flutter]
final tick = ref(context, 0);
final duration = ref(context, const Duration(seconds: 1))

effect(context, () {
    // Listen to duration.value and create an internal Timer.
    final timer = Timer.periodic(duration.value, (timer) {
        tick.value = timer.tick;
    });

    // Stop the previous Timer before duration updates.
    onEffectCleanup(() {
        if (timer.isActive) timer.cancel();
    });
});
```
:::

### Stop Effect

When we don't want the side effect function to continue listening to reactive properties, we can stop it like this:

::: code-group
```dart [Dart]
final runner = effect(() => ...);

// Stop the side effect from listening to reactive properties.
runner.effect.stop();
```
```dart [Flutter]
final runner = effect(context, () => ...);

// Stop the side effect from listening to reactive properties.
runner.effect.stop();
```
:::

### Pause/Resume

Sometimes, we want to pause rather than terminate the listener:

::: code-group
```dart [Dart]
final runner = effect(() => ...);

// Pause
runner.effect.pause();

// Resume later
runner.effect.resume();
```
```dart [Flutter]
final runner = effect(context, () => ...);

// Pause
runner.effect.pause();

// Resume later
runner.effect.resume();
```
:::

## Watcher (`watch()`)

Watches one or more reactive data sources constructed as a `Record`, and calls the given callback function when the data source changes.

- `watch()` Type Signature:
  ::: code-group
  ```dart [Dart]
  WatchHandle watch<T extends Record>(
    T Function() compute,
    void Function(T value, T? oldValue) runner, {
    bool immediate = false,
    bool once = false,
  })
  ```
  ```dart [Flutter]
  WatchHandle watch<T extends Record>(
    BuildContext context,
    T Function() compute,
    void Function(T value, T? oldValue) runner, {
    bool immediate = false,
    bool once = false,
  })
  ```
  :::
- Type:
  ```dart
  extension type WatchHandle {
    void stop();
    void pause();
    void resume();
    void call(); // Callable overload symbol, equivalent to stop()
  }
  ```
- Details:

  `watch()` behaves consistently with [effect](#side-effect-effect), but there are some functional differences

  > 1. Uses a computation function to encapsulate multiple values into a `Record`
  > 2. The runner provides both new and old values.
  > 3. By default, it's lazy watching, meaning the callback function is only executed when the watched source changes.

  - `immediate`: Triggers the callback immediately when the watcher is created. The old value is `null` on the first call.
  - `once`: The callback function will only run once. The watcher will automatically stop after the callback function runs for the first time.
- Example:

  Watching a `Ref<T>`:
  ::: code-group
  ```dart [Dart]
  final count = ref(0);
  watch(
      () => (count.value),
      (value, prev) {...}
  );
  ```
  ```dart [Flutter]
  final count = ref(context, 0);
  watch(
      context,
      () => (count.value),
      (value, prev) {...}
  );
  ```
  :::

  Watching multiple:

  ::: code-group
  ```dart [Dart]
  final count = ref(0);
  final plusOne = derived(() => count + 1);
  watch(
      () => (count.value, plusOne.value),
      (value, prev) {...}
  );
  ```
  ```dart [Flutter]
  final count = ref(context, 0);
  final plusOne = derived(context, () => count + 1);
  watch(
      context,
      () => (count.value, plusOne.value),
      (value, prev) {...}
  );
  ```
  :::

### Stopping the Watcher

```dart
final stop = watch(...);

stop(); // Stop the watcher
```

### Pause/Resume Watcher

```dart
final WatchHandle(:stop, :pause, :resume) = watch(...);

pause(); // Pause the watcher
resume(); // Resume watching later
stop(); // Stop
```

### Watcher Side Effect Cleanup

In `watch()`, like in [Effect - Side Effect Cleanup](#side-effect-cleanup), we use the `onEffectCleanup()` function.

> [!IMPORTANT] Friendly Reminder
> `watch()` is highly optimized based on `effect()`.
