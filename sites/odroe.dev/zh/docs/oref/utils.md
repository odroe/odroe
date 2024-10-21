---
title: 文档 → Oref - 工具函数
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Oref - 工具函数
---

本章将为你讲解一些 Oref 的实用工具。

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

## `compose()` <Badge type="tip" text="Flutter" /> {#compose}

`compose()` 将传入的函数原样并进行正确的类型包装：

```dart
final useCounter = compose((BuildContext context) {
    final count = ref(context, 0);

    void increment() => count.value++;

    return (
        valueOf: () => count.value,
        increment: increment
    );
});
```

### 为什么需要它？ {#compose-why-do-need-it}

当我们使用 Oref 的反应性 API 来构造制造新的可组合 API 时，Dart 函数通常需要我们显示定义 `out Type`：

```dart
({T Function() valueOf, void Function() increment}) useCountter(BuildContext context) {
    final count = ref(context, 0);

    void increment() => count.value++;

    return (
        valueOf: () => count.value,
        increment: increment
    );
}
```

这给让我们增加了大量的样板代码。

### lint 规则警告 {#compose-lint-rule-warn}

虽然使用变量定义函数可以达到完全一致的效果：

```dart
final useCounter = (BuildContext context) {
    final count = ref(context, 0);

    void increment() => count.value++;

    return (
        valueOf: () => count.value,
        increment: increment
    );
}
```

但 lint rules 会发出不规范的警告，因此，我们应该使用 `compose()` 来进行包装，并无需编写样板类型。

### 手动实现 {#compose-manual-impl}

`compose()` 并不是什么高深的技术，它仅仅一行代码：

```dart
F compose<F extends Function>(F fn) => fn;
```
