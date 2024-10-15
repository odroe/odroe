---
title: 文档 → Oref - 进阶
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Oref - 进阶
next: false
---

## `createScope()` {#create-scope}

创建一个 effect 作用域，可以捕获其中所创建的响应式副作用 (即计算属性和侦听器)，这样捕获到的副作用可以一起处理。

- 类型
  ::: code-group
  ```dart [Dart]
  Scope createScope([bool detached = false])
  ```
  ```dart [Flutter]
  Scope createScope(BuildContext context, [bool detached = false])
  ```
  :::
- 返回类型
  ```dart
  abstract interface class Scope {
      T? run<T>(T Function() runner); // 当作用域不活跃时，返回 null
      void stop();
      void pause();
      void resume();
      void on();
      void off();
  }
  ```
- 示例
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

  // 处理掉当前作用域内的所有 effect
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

  // 处理掉当前作用域内的所有 effect
  scope.stop();
  ```
  :::

### 暂停/恢复作用域 {#pause-resume-scope}

`Scope` 对象公开 `pause()`/`resume()` 方法，允许你临时暂停和恢复作用域中的所有副作用。
它与 effect 类似，区别在于 scope 通常用于批量管理 effect。

### 进阶操作 {#advanced-operations}

`Scope` 暴露了两个低 API `on()`/`off()`，通常适用于对 Oref 的深度定制使用。

- `on()`: 将全局评估作用域设置为当前活跃的作用域。
- `off()`: 将全局评估作用域设置为当前作用域的父辈作用域。

> 例如，在 Oref 的 Flutter 集成中，我们就使用了它来暂停和恢复收集 Widget 内的响应性范围。

## `getCurrentScope()` {#get-current-scope}

如果有的话，返回当前活跃的 effect 作用域。

- 类型
  ```dart
  Scope? getCurrentScope();
  ```

## `onScopeDispose()` {#on-scope-dispose}

在当前活跃的 effect 作用域上注册一个处理回调函数。当相关 effect 作用域停止时会调用这个回调函数。

## `triggerRef()` {#trigger-ref}

强制触发依赖于一个 `Ref<T>` 的副作用，这通常在对浅引用的内部值进行深度变更后使用。

- 类型
  ```dart
  void triggerRef<T>(Ref<T> ref)
  ```
- 示例
  ```dart
  final shallow = ref({'greet': 'Hello'});

  // 打印：Hello
  effect(() => print(shallow.value['greet']));

  // 这里不会触发 effect 副作用的运行，因为 shallow 是一个浅层的。
  shallow.value['greet'] = 'Hi!!!';

  // 打印：Hi!!!
  triggerRef(shallow);
  ```
