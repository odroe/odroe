---
title: Documentation → Oref - Advanced
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Oref - Advanced
next: false
---

## `batch()` <Badge type="tip" text="v0.4+" /> {#batch}

`batch()` allows you to merge multiple reactive collections and ref triggers into a single operation.

- Type

  ```dart
  void batch(void Function() runner);
  ```

- Details

  When your side effects depend on multiple refs or reactive collections, each reactive state update triggers the side effect to run. Sometimes we need to update multiple values simultaneously but want to trigger the side effect only once.

- Example

  ```dart
  final a = ref(0);
  final b = ref(0);

  // a + b = 0
  effect(() {
    print('a + b = ${a.value + b.value}');
  });

  // a + b = 3;
  batch(() {
    a.value = 1;
    b.value = 2;
  });

  // a + b = 4
  a.value = 2;

  // a + b = 5
  b.value = 3;
  ```

  Can be used nested:
  ```dart
  // a + b = 3
  batch(() {
    batch(() {
      a.value = 1;
    });

    b.value = 2;
  });
  ```

## `createScope()` {#create-scope}

Creates an effect scope that can capture reactive side effects (i.e., computed properties and watchers) created within it, allowing the captured side effects to be handled together.

- Type
  ::: code-group
  ```dart [Dart]
  Scope createScope([bool detached = false])
  ```
  ```dart [Flutter]
  Scope createScope(BuildContext context, [bool detached = false])
  ```
  :::
- Return Type
  ```dart
  abstract interface class Scope {
    T? run<T>(T Function() runner); // Returns null when the scope is inactive
    void stop();
    void pause();
    void resume();
    void on();
    void off();
  }
  ```
- Example
  ::: code-group
  ```dart [Dart]
  final scope = createScope();

  scope.run(() {
    final doubled = derived(() => counter.value * 2);

    watch(
      () => (doubled.value),
      (value, _) => print(value.$1),
    );

    effect(() => print('Double Count: ${doubled.value}'));
  });

  // Dispose of all effects within the current scope
  scope.stop();
  ```
  ```dart [Flutter]
  final scope = createScope(context);

  scope.run(() {
    final doubled = derived(context, () => counter.value * 2);

    watch(
      context,
      () => (doubled.value),
      (value, _) => print(value.$1),
    );

    effect(context, () => print('Double Count: ${doubled.value}'));
  });

  // Dispose of all effects within the current scope
  scope.stop();
  ```
  :::

### Pause/Resume Scope {#pause-resume-scope}

The `Scope` object exposes `pause()`/`resume()` methods, allowing you to temporarily pause and resume all side effects within the scope.
It's similar to effect, but the difference is that scope is typically used for batch management of effects.

### Advanced Operations

`Scope` exposes two low-level APIs `on()`/`off()`, typically used for deep customization of Oref.

- `on()`: Sets the global evaluation scope to the current active scope.
- `off()`: Sets the global evaluation scope to the parent scope of the current scope.

> For example, in Oref's Flutter integration, we use it to pause and resume collecting reactive ranges within Widgets.

## `getCurrentScope()` {#get-current-scope}

Returns the current active effect scope, if any.

- Type
  ```dart
  Scope? getCurrentScope();
  ```

## `onScopeDispose()` {#on-scope-dispose}

Registers a cleanup callback function on the current active effect scope. This callback function will be called when the related effect scope stops.

## `triggerRef()` {#trigger-ref}

Forcibly triggers side effects dependent on a `Ref<T>`, typically used after making deep changes to the internal value of a shallow reference.

- Type
  ```dart
  void triggerRef<T>(Ref<T> ref)
  ```
- Example
  ```dart
  final shallow = ref({'greet': 'Hello'});

  // Prints: Hello
  effect(() => print(shallow.value['greet']));

  // This won't trigger the effect side effect to run, because shallow is a shallow reference.
  shallow.value['greet'] = 'Hi!!!';

  // Prints: Hi!!!
  triggerRef(shallow);
  ```

## `customRef()` <Badge type="tip" text="v0.4+" /><Badge type="info" text="oref_flutter: v0.3+" /> {#custom-ref}

Creates a custom ref with explicit control over its dependency tracking and triggering of effects.

- Type

  ::: code-group
  ```dart [dart]
  Ref<T> customRef<T>(Factory<T> factory);
  ```
  ```dart [flutter]
  Ref<T> customRef<T>(BuildContext context, Factory<T> factory);
  ```
  :::

  ```dart
  typedef FactoryResult<T> = ({
    T Function() get,
    void Function(T) set
  });

  typedef Factory<T> = FactoryResult<T> Function(
    void Function() track,
    void Function() trigger,
  );
  ```

- Details

  `customRef()` expects a factory function as a parameter. This factory function receives two functions, `track` and `trigger`, as parameters,
  and returns a Record with two properties: `get` and `set`.

  Generally, `track()` should be called in the `get()` method, while `trigger()` should be called in `set()`.
  However, you have complete control over when and whether to call them.

- Example

  Create a debounced ref, which only calls after a fixed interval following the most recent set call:
  ::: code-group
  ```dart [dart]
  Ref<T> useDebouncedRef<T>(T value, [Duration delay = const Duration(milliseconds: 200)]) {
    Timer? timer;
    return customRef<T>((track, trigger) => (
      get: () {
        track();
        return value;
      },
      set: (newValue) {
        timer?.cancel();
        timer = Timer(delay, () {
          value = newValue;
          trigger();
        });
      }
    );
  }
  ```
  ```dart [flutter]
  Ref<T> useDebouncedRef<T>(BuildContext context ,T value, [
    Duration delay = const Duration(milliseconds: 200)
  ]) {
    Timer? timer;
    return customRef<T>(context, (track, trigger) => (
      get: () {
        track();
        return value;
      },
      set: (newValue) {
        timer?.cancel();
        timer = Timer(delay, () {
          value = newValue;
          trigger();
        });
      }
    );
  }
  ```
  :::

## `toRaw()` <Badge type="tip" text="v0.4+" /> {#to-raw}

Returns the original collection object based on a reactive collection.

- Type

  ```dart
  T toRaw<T>(T reactive);
  ```

- Details

  `toRaw()` can return the original collection corresponding to objects created by [reactive collections](/docs/oref/core#reactive-collections) (`reactiveMap`, `reactiveSet`, `reactiveList`, `reactiveIterable`).

- Example

  ```dart
  final original = {1, 2}; // Set<int>
  final observed = reactiveSet(original); // Set<int>

  print(toRaw(observed) == original); // true
  ```

## `untracked()` <Badge type="tip" text="v0.4+" /> {#untracked}

In rare cases, we expect to read the value of a ref or reactive collection without it being tracked. This is where we need `untracked()`.

- Type

  ```dart
  T untracked<T>(T Function() runner);
  ```

- Details

  The usage of `untracked()` is essentially the same as read-only derivation (`derived()`), but it doesn't track reactions.
  Therefore, we can use it to prevent certain values from affecting side effects.

- Example

  ```dart
  final a = ref(0);
  final b = ref(0);

  // a + b = 0
  effect(() {
    final value = untracked(() => a.value);
    print('a + b = ${value + a.value}');
  });

  // No effect
  a.value = 1;

  // a + b = 2
  b.value = 2;
  ```
