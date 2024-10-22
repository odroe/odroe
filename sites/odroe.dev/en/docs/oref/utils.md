---
title: Documentation → Oref Utility Functions
description: This chapter provides a detailed introduction to the utility functions offered by Oref. These functions are designed to simplify the development process, improve code efficiency, and enhance type safety. Whether you're dealing with reactive references, performing type checks, or optimizing Flutter widgets, the utility functions here can provide powerful support for your development work.
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Oref Utility Functions
---

{{ $frontmatter.description }}

## `isRef()` {#is-ref}

Checks if a value is a `Ref<T>`.

- Type

  ```dart
  bool isRef(Object? value);
  ```

`isRef()` doesn't declare anything special, it's just a functional encapsulation of `is`. If you don't like the function style, you can completely use `value is Ref` instead.

## `isReactive()` <Badge type="tip" text="v0.4+" /> {#is-reactive}

Checks if an object is a [reactive collection](/docs/oref/core#reactive-collections).

- Type
  ```dart
  bool isReactive<T>(T value);
  ```


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

When using your Widget with Oref, if you use `this.name`, it only takes effect on the first build.
When you update the `name` parameter of `MyWidget` in the ancestor, since `name` is not reactive, `rebuild` will not
take effect in Oref's scope. Let's look at this simple example:

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

No matter how we update the value of `correct` in the upper layer, it won't take effect. The reason is that ordinary objects are not reactive, so we need to convert `correct` to a reactive value.
But if we wrap every property reactively, it would be too troublesome, after all, there may be many property values in real scenarios.
So converting the entire Widget object to Ref is the most secure way:

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

## Infer Return Type (`inferReturnType()`) <Badge type="tip" text="v0.5+" /> {#infer-return-type}

The `inferReturnType()` function is used to infer and correctly wrap the return type of the input function:

```dart
// Inferred return type: ({String name, DateTime createdAt})
final say = inferReturnType((String name) => (name: name, createdAt: DateTime.now()));
```

### Why do we need it? {#why-do-need-infer-return-type}

When building new composable APIs using Oref's reactive API, Dart usually requires us to explicitly define the function's return type:

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

This approach leads to a lot of boilerplate code, reducing code readability and maintainability.

### Avoiding lint rule warnings {#avoid-lint-rule-warn}

Although using variable-defined functions can achieve a similar effect:

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

This approach triggers a lint rule warning (`prefer_function_declarations_over_variables`). To avoid this issue and prevent writing lengthy type declarations, we can use the `inferReturnType()` function.

### Implementation principle {#infer-return-type-impl}

The implementation of `inferReturnType()` is very simple, requiring only one line of code:

```dart
F inferReturnType<F extends Function>(F fn) => fn;
```

This function utilizes Dart's type inference mechanism to help developers maintain code conciseness and type safety without explicitly declaring complex return types.
