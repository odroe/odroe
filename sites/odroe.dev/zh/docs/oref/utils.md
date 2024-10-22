---
title: 文档 → Oref 工具函数
description: 本章节详细介绍了 Oref 提供的实用工具函数。这些函数旨在简化开发过程，提高代码效率，并增强类型安全性。无论您是在处理响应式引用、进行类型检查，还是优化 Flutter 小部件，这里的工具函数都能为您的开发工作提供有力支持。
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Oref 工具函数
---

{{ $frontmatter.description }}

## `isRef()` {#is-ref}

检查一个值是否是 `Ref<T>`。

- 类型

  ```dart
  bool isRef(Object? value);
  ```

`isRef()` 没有声明特别的，它只是 `is` 的函数式封装。如果你不喜欢函数风格，你完全可以使用 `value is Ref` 替代。

## `isReactive()` <Badge type="tip" text="0.4+" /> {#is-reactive}

检查一个对象是否是一个[响应式集合](/zh/docs/oref/core#reactive-collections)。

- 类型
  ```dart
  bool isReactive<T>(T value);
  ```

## `unref()` {#unref}

如果参数是一个 `Ref<T>` 那么返回其内部的响应式值，否则返回本身。

这是 `return isRef(value) ? value.value : value` 的三元计算语法糖。

- 类型
  ```dart
  R unref<R>(R value);
  R unref<R>(Ref<R> ref);
  ```
- 示例
  ```
  useCounter(/* int | Ref<int> */ count) {
    final int unwrapped = unref(count);
    // unwrapped 现在保证为 number 类型
  }
  ```
- 注意事项
  适用于你确定变量是 `T | Ref<T>` 类型实用，如果你无法确定类型，请使用 dynamic 进行接收：
  ```dart
  final unwrapped = unref(value);
  ```

## `toWidgetRef()` <Badge type="tip" text="Flutter" /> {#to-widget-ref}

将一个 Widget 对象转换为 `Ref<T extends Widget>` 对象的引用。

```dart
import 'package:oref_flutter/oref_flutter.dart';

class MyWidget extends StatelessWidget {
    const MyWidget({super.key, required this.name});

    final String name;

    Widget build(BuildContext context) {
        final widgetRef = toWidgetRef(context, this);
        effect(() => print(widgetRef.value.name);

        return ...;
    }
}
```

当你的 Widget 与 Oref 进行搭配使用时，如果你使用 `this.name` 仅在第一次 build 时生效。
当你在祖先更新 `MyWidget` 的 `name` 参数时，由于 `name` 并非响应式的，因此 `rebuild` 不会在
Oref 的作用域中生效。我们看这个简单的例子：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key, required this.correct});

    final int correct;

    Widget build(BuildContext context) {
        final count = ref(context, 0);
        final computed = derived(() => count.value + correct);

        return TextButton(
            onPressed: () => count.value++,
            child: Text('${computed.value}'),
        );
    }
}
```

在上层无论我们如何更新 `correct` 的值，都不会生效。原因普通对象不具备响应性，因此我们需要将 `correct` 转换为响应式的值。
但如果我们为每一个属性都进行响应式包装未免也太过于麻烦，毕竟实际场景下可能会有许多属性值。
所以将整个 Widget 对象转换为 Ref 是最为稳妥的方式：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key, required this.correct});

    final int correct;

    Widget build(BuildContext context) {
        final widgetRef = toWidgetRef(context, this);
        final count = ref(context, 0);
        final computed = derived(() => count.value + widgetRef.value.correct);

        return TextButton(
            onPressed: () => count.value++,
            child: Text('${computed.value}'),
        );
    }
}
```

## 推测返回类型（`inferReturnType()`） <Badge type="tip" text="v0.5+" /> {#infer-return-type}

`inferReturnType()` 函数用于推断并正确包装传入函数的返回类型：

```dart
// 推断的返回类型: ({String name, DateTime createdAt})
final say = inferReturnType((String name) => (name: name, createdAt: DateTime.now()));
```

### 为什么需要它？ {#why-do-need-infer-return-type}

在使用 Oref 的响应式 API 构建新的可组合 API 时，Dart 通常要求我们显式定义函数的返回类型：

```dart
({T Function() valueOf, void Function() increment}) useCounter<T>() {
  final count = ref(0);
  void increment() => count.value++;

  return (
    valueOf: () => count.value as T,
    increment: increment
  );
}
```

这种做法会导致大量样板代码，降低了代码的可读性和维护性。

### 规避 lint 规则警告 {#avoid-lint-rule-warn}

虽然使用变量定义函数可以达到类似的效果：

```dart
final useCounter = () {
  final count = ref(0);
  void increment() => count.value++;

  return (
    valueOf: () => count.value,
    increment: increment
  );
};
```

但这种写法会触发 lint 规则警告（`prefer_function_declarations_over_variables`）。为了规避这个问题并避免编写冗长的类型声明，我们可以使用 `inferReturnType()` 函数。

### 实现原理 {#infer-return-type-impl}

`inferReturnType()` 的实现非常简单，仅需一行代码：

```dart
F inferReturnType<F extends Function>(F fn) => fn;
```

这个函数利用 Dart 的类型推断机制，帮助开发者在不显式声明复杂返回类型的情况下，保持代码的简洁性和类型安全性。
