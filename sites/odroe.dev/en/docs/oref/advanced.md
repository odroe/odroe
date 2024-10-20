---
title: Documentation → Oref - Advanced
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Oref - Advanced
next: false
---

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
它与 effect 类似，区别在于 scope 通常用于批量管理 effect。

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

Registers a cleanup callback function on the current active effect scope. This callback function will be called when the related effect scope stops.当相关 effect 作用域停止时会调用这个回调函数。

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
