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

### Why do we need it? {#compose-why-do-need-it}

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
