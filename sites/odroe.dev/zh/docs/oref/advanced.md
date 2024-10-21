---
title: 文档 → Oref - 进阶
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Oref - 进阶
next: false
---

## `batch()` <Badge type="tip" text="v0.4+" /> {#batch}

`batch()` 允许你一次性将多个响应式集合和 ref 触发合并为一次。

- 类型

  ```dart
  void batch(void Function() runner);
  ```

- 详细信息

  当你的副作用依赖于多个 ref 或者响应式集合时，每一个响应性状态更新都会触发副作用运行。有时候我们需要将多个值同时
  更新，但希望仅触发一次副作用。

- 示例

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

  可以嵌套使用：
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

## `customRef()` <Badge type="tip" text="v0.4+" /><Badge type="info" text="oref_flutter: v0.3+" /> {#custom-ref}

创建一个自定义的 ref，显式声明对其依赖追踪和更新触发的控制方式。

- 类型

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

- 详细信息

  `customRef()` 预期收到一个工厂函数作为参数，这个工厂函数接收 `track` 和 `trigger` 两个函数作为参数，
  并返回一个属性具有 `get` 和 `set` 的两个 `Record`。

  一般而言，`track()` 应该在 `get()` 方法中调用，而 `trigger()` 则应该在 `set()` 中调用。
  然而事实上，你对何时调用、是否应该调用他们拥有完全的控制权。

- 示例

  创建一个防抖 ref,即只在最近一次 set 调用后的一段固定间隔后再调用：
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

## `toRaw()` <Badge type="tip" text="0.4+" /> {#to-raw}

根据一个响应式集合返回其原始集合对象。

- 类型

  ```dart
  T toRaw<T>(T reactive);
  ```

- 详细信息

  `toRaw()` 可以返回由[响应式集合](/zh/docs/oref/core#reactive-collections)（`reactiveMap`、`reactiveSet`、`reactiveList`、`reactiveIterable`）
  所创建的对象所对应的原始集合。

- 示例

  ```dart
  final original = {1, 2}; // Set<int>
  final observed = reactiveSet(original); // Set<int>

  print(toRaw(observed) == original); // true
  ```

## `untracked()` <Badge type="tip" text="v0.4+" /> {#untracked}

在少数情况下，我们期待读取 ref 或者响应式集合的值不会被跟踪，这时候我们就需要 `untracked()`。

- 类型

  ```dart
  T untracked<T>(T Function() runner);
  ```

- 详细信息

  `untracked()` 使用方法本质上和只读派生（`derived()`）一样的用法，但它不会跟踪响应。
  因此，我们可以用来阻止某些值对副作用的影响。

- 示例

  ```dart
  final a = ref(0);
  final b = ref(0);

  // a + b = 0
  effect(() {
    final value = untracked(() => a.value);
    print('a + b = ${value + a.value}');
  });

  // 无效果
  a.value = 1;

  // a + b = 2
  b.value = 2;
  ```
