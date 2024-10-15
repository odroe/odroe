---
title: 文档 → Oref - 核心 API
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Oref - 核心 API
---

Oref 核心 API

## 引用（`ref()`）

接收一个内部值，返回一个响应式的、可更改的 `Ref<T>` 对象，这个对象只有一个指向其内部值的属性 `.value`。

- 类型：
  ::: code-group
  ```dart [Dart]
  Ref<T> ref<T>(T value);
  ```
  ```dart [Flutter]
  Ref<T> ref<T>(BuildContext context, T value);
  ```
  :::
- 返回类型：
  ```dart
  abstract interface class Ref<T> {
      T value;
  }
  ```
- 详细信息

  `Ref<T>` 对象是可更改的，也就是说我们可以使用 `.value` 赋予新的值。它也是响应式的，即对所有读取了 `.value` 的操作都将被追踪，并且赋值操作会触发与之相关的副作用。

- 示例：
  ```dart
  final count = ref(0);
  print(count.value); // 0

  count.value = 1;
  print(count.value); // 1
  ```

## 派生（`derived()`）

`derived()`接收一个 getter 函数（类型：`T Function()`），返回一个只读的响应式 `Derived<T>` 对象。该 `Derived<T>` 通过 `.value`
暴露 getter 函数的返回值。

- 类型：
  ::: code-group
  ```dart [Dart]
  Derived<T> derived<T>(T Function() getter);
  ```
  ```dart [Flutter]
  Derived<T> derived<T>(BuildContext context, T Function() getter);
  ```
  :::
- 返回类型
  ```dart
  abstract interface class Derived<T> extends Ref<T> {
      T get value;
  }
  ```
- 示例
  ::: code-group
  ```dart [Dart]
  final count = ref(1);
  final plusOne = derived(() => count.value + 1);

  print(plusOne.value); // 2

  plusOne.value++; // 无效，Dart VM 下在 DevTools console 中输出警告
  ```
  ```dart [Flutter]
  final count = ref(context, 1);
  final plusOne = derived(context, () => count.value + 1);

  print(plusOne.value); // 2

  plusOne.value++; // 无效，Flutter dev 模式下在 DevTools console 中输出警告
  ```
  :::

### 带值的派生（`derived.valuable()`）

有时候我们实现派生时，需要使用上一个值加入到计算中，那么就需要 `derived.valuable`：

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

### 可写的派生（`derived.writable()`）

可写的派生允许你实现类似逆转计算的功能，我们需要用到 `derived.writable()` 函数：

::: code-group
```dart [Dart]
final count = ref(0);
final doubleCount = derived.writable<int>(
    (_) => count.value * 2, // count 乘 2
    (value) => count.value = value ~/ 2, // 逆转计算，反向操作 count
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
    (_) => count.value * 2, // count 乘 2
    (value) => count.value = value ~/ 2, // 逆转计算，反向操作 count
);

doubleCount.value = 10;
print(count.value); // 5

count.value = 10;
print(doubleCount.value); // 20
```
:::

由此，我们可以直接在派生响应式之上直接实现可逆转的响应式数据操作。

## 副作用（`effect()`）

立即运行一个函数，同时响应式地追踪函数内所使用的响应式数据作为依赖，并在被追踪的依赖更改时重新执行函数：

- 类型
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
- 返回类型
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
  > 点击"[Effect\<T\> class API](https://pub.dev/documentation/oref/latest/oref/Effect-class.html)" 查看更多信息
- 详细信息
  - `context`: Flutter Widget 的上下文。<Badge type="tip" text="Flutter" />
  - `runner`: 需要执行的副作用函数。
  - `scheduler`: 自定义副作用触发器
  - `onStop`: 当副作用被停止时执行。
- 示例：
  ::: code-group
  ```dart [Dart]
  final count = ref(0);

  effect(() => print(count.value));
  // -> 打印 0

  count.value++;
  // -> 打印 1
  ```

  ```dart [Flutter]
  final count = ref(context, 0);

  effect(context, () => print(count.value));
  // -> 打印 0

  count.value++;
  // -> 打印 1
  ```
  :::

### 副作用清除

有时候，我们在重新运行副作用函数之前，运行另一个函数对之前的资源进行清理：

::: code-group
```dart [Dart]
final tick = ref(0);
final duration = ref(const Duration(seconds: 1))

effect(() {
    // 监听 duration.value 并创建一个内部 Timer。
    final timer = Timer.periodic(duration.value, (timer) {
        tick.value = timer.tick;
    });

    // 当 duration 更新之前，停止上一个 Timer。
    onEffectCleanup(() {
        if (timer.isActive) timer.cancel();
    });
});
```
```dart [Flutter]
final tick = ref(context, 0);
final duration = ref(context, const Duration(seconds: 1))

effect(context, () {
    // 监听 duration.value 并创建一个内部 Timer。
    final timer = Timer.periodic(duration.value, (timer) {
        tick.value = timer.tick;
    });

    // 当 duration 更新之前，停止上一个 Timer。
    onEffectCleanup(() {
        if (timer.isActive) timer.cancel();
    });
});
```
:::

### 终止副作用

当我们不希望副作用函数继续侦听响应式属性时，我们可以这样停止它：

::: code-group
```dart [Dart]
final runner = effect(() => ...);

// 停止副作用对响应式属性的侦听。
runner.effect.stop();
```
```dart [Flutter]
final runner = effect(context, () => ...);

// 停止副作用对响应式属性的侦听。
runner.effect.stop();
```
:::

### 暂停/恢复

有时候，我们希望暂停而不是终止侦听器：

::: code-group
```dart [Dart]
final runner = effect(() => ...);

// 暂停
runner.effect.pause();

// 稍后恢复
runner.effect.resume();
```
```dart [Flutter]
final runner = effect(context, () => ...);

// 暂停
runner.effect.pause();

// 稍后恢复
runner.effect.resume();
```
:::

## 侦听器（`watch()`）

侦听一个或多个响应式数据源构造为 `Record`，并在数据源变化时调用所给的回调函数。

- `watch()` 类型签名
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
- 类型
  ```dart
  extension type WatchHandle {
    void stop();
    void pause();
    void resume();
    void call(); // 可调用重载符号，等同于 stop()
  }
  ```
- 详细信息

  `watch()` 与 [effect](#副作用-effect) 行为一致，但存在一些功能差异

  > 1. 采用计算函数的方式将多个值封装成 `Record`
  > 2. runner 同时提供新值和久值。
  > 3. 默认时懒监听的，即仅在侦听源发生变化时才执行回调函数。

  - `immediate`: 在侦听器创建时立即触发回调。第一次调用时旧值是 `null`。
  - `once`: 回调函数只会运行一次。侦听器将在回调函数首次运行后自动停止。
- 示例

  侦听一个 `Ref<T>`:
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

  侦听多个：

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

### 停止侦听器

```dart
final stop = watch(...);

stop(); // 停止侦听器
```

### 暂停/恢复侦听器

```dart
final WatchHandle(:stop, :pause, :resume) = watch(...);

pause(); // 暂停侦听器
resume(); // 稍后回复侦听
stop(); // 停止
```

### 侦听器的副作用清理

在 `watch()` 中和在 [Effect - 副作用清除](#副作用清除) 一样，都是使用 `onEffectCleanup()` 函数。

> [!IMPORTANT] 温馨提示
> `watch()` 是基于 `effect()` 进行高度优化封装的。

## 可观测（`obs()`）<Badge type="tip" text="Flutter" /><Badge type="info" text="oref_flutter: 0.2+" />

`obs()` 允许你观测一个 `Ref<T>` 并获取它的值构造 Widget，当 ref 更新时，仅仅更新这一个 Widget 而不是重建当前 Widget 树的所有节点：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: obs(count, (count) => Text('Count: ${count}')), // [!code focus]
        );
    }
}
```

当 `count` 内部的值更新时，只会重建 `Text` Widget而不会让整个 `Counter` 重建。

如果你更喜欢函数式编程，也许你会更喜欢这样的使用方法：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: count.obs((count) => Text('Count: ${count}')), // [!code focus]
        );
    }
}
```
