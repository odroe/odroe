---
title: Documentation → Oref - Utility Functions
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Oref - Utility Functions
---

This chapter will explain some useful tools in Oref.

## `isRef()` {#is-ref}

Checks if a value is a `Ref<T>`.

- Implementation
  ```dart
  bool isRef(Object? value) => value is Ref;
  ```

`isRef()` doesn't declare anything special, it's just a functional encapsulation of `is`. If you don't like the function style, you can completely use `value is Ref` instead.如果你不喜欢函数风格，你完全可以使用 `value is Ref` 替代。

## `unref()` {#unref}

If the parameter is a `Ref<T>`, it returns its internal reactive value, otherwise it returns itself.

This is a ternary computation syntactic sugar for `return isRef(value) ? value.value : value`.

- Types
  ```dart
  R unref<R>(R value);
  R unref<R>(Ref<R> ref);
  ```
- Example
  ```
  useCounter(/* int | Ref<int> */ count) {
    final int unwrapped = unref(count);
    // unwrapped is now guaranteed to be of number type
  }
  ```
- Note
  Applicable when you are sure the variable is of type `T | Ref<T>`. If you can't determine the type, please use dynamic to receive:
  ```dart
  final unwrapped = unref(value);
  ```

## `toWidgetRef()` <Badge type="tip" text="Flutter" /> {#to-widget-ref}

Converts a Widget object to a reference of a `Ref<T extends Widget>` object.

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
When using your Widget with Oref, if you use `this.name`, it only takes effect on the first build.
When you update the `name` parameter of `MyWidget` in the ancestor, since `name` is not reactive, `rebuild` will not
take effect in Oref's scope. Let's look at this simple example:我们看这个简单的例子：

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

`compose()` passes the input function as-is and performs correct type wrapping:

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

### 为什么需要它？ Why do we need it? {#compose-why-do-need-it}

When we use Oref's reactive API to construct new composable APIs, Dart functions usually require us to explicitly define `out Type`:

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

This adds a lot of boilerplate code for us.

### lint rule warning {#compose-lint-rule-warn}

Although using variables to define functions can achieve the same effect:

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

But lint rules will issue non-standard warnings, so we should use `compose()` to wrap it, and there's no need to write boilerplate types.

### Manual implementation {#compose-manual-impl}

`compose()` is not a sophisticated technique, it's just one line of code:

```dart
F compose<F extends Function>(F fn) => fn;
```
