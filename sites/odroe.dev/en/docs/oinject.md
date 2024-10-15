---
title: Documentation → Dependency Injection (Oinject)
description: Oinject is a simple yet powerful dependency injection package that allows an ancestor component to act as a dependency injector for its descendant components, regardless of how deep the component hierarchy is, as long as they are on the same component chain.
head:
  - - meta
    - property: og:title
      content: Odroe | Documentation → Dependency Injection (Oinject)
prev: false
next: false
---

Typically, when we need to pass data from a parent Widget to a child Widget, we use Widget constructor parameters. However, our Widget structure is often multi-layered, forming a large Widget Tree. A child Widget at a deeper level may need some data from a distant ancestor Widget. In this case, using only constructor parameters to pass data down the Widget chain level by level can be very cumbersome.

::: tip
We can read [Flutter Simple State Management - Lifting state up](https://docs.flutter.dev/data-and-backend/state-mgmt/simple#lifting-state-up) to understand its importance.
:::

## Why do we need Oinject? {#why-do-we-need-oinject}

In the Flutter ecosystem, there are many packages that can do similar things, such as [Provider](https://pub.dev/packages/provider). Even Flutter itself comes with a simple way to provide data: [InheritedWidget](https://api.flutter.dev/flutter/widgets/InheritedWidget-class.html).

The advantage of Oinject lies in its minimal boilerplate code and ease of use. Here's a simple comparison:

| Name | Boilerplate Code | Widget Tree Pollution | Support Data Stacking |
|-----|----|----|----|
| `provider` | Moderate | Pollutes | Not Supported |
| InheritedWidget | High | Pollutes | Not Supported |
| `oinject` | Low | No | Supported |

Most importantly, Oinject can work with any Widget (as long as it has a `BuildContext`). This provides great convenience for migrating your existing App to Oinject.

## Installation {#installation}

We run the following command:

```bash
flutter pub add oinject
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  oinject: latest
```

## Provide {#provide}

To provide data to Widget descendants, we need to use the `provide()` function:

```dart
class MyWidget extends StatelessWidget {
    Widget build(BuildContext context) {
        provide(context, 'value');

        return ...;
    }
}
```

The `provide()` function accepts three values and one type parameter. The first parameter is the build context of Flutter Widgets (called `BuildContext`, we usually use `context` to receive it). The second parameter is the specific value to be provided, which matches the type parameter (pseudocode: `<T>(T value)`). The third parameter is the type data Key used for data stacking, designed as a Symbol type:

```dart
provide(context, 'value', key: #hello);
```

The greatest use of Key is to accurately annotate data (relying on type parameters is not reliable) or to stack data of different types:

```dart
provide(context, key: #user, 1);
provide(context, key: #user, 'Seven');
```

With this, we can easily pass the User's ID and Name to descendants. (Only applicable to type data that does not conflict)

## Global Provide {#global-provide}

In addition to providing data in the Widget tree, you may also want to provide global data at the entry point of the Flutter application. We need to use the `provide.global()` function:

```dart
void main() {
    provide.global('value');

    runApp(const App());
}
```

The only difference between `provide.global()` and `provide` is that global provision does not require the `BuildContext` parameter. It only has two parameters, corresponding to the second and third parameters of `provide()`:

```dart
void main() {
    provide.global(key: #user, 1);
    provide.global(key: #user, 'name');

    runApp(const App());
}
```

## Inject {#inject}

To inject data provided by upper-level Widgets, use the `inject` function:

```dart
class ChildWidget extends StatelessWidget {
    Widget build(BuildContext context) {
        final name = inject<String>(context);

        return ...;
    }
}
```

Injection with Key:

```dart
final id = inject<int>(context, #user);
final name = inject<String>(context, #user);
```

### Default Injection Value {#default-injection-value}

By default, `inject()` assumes that the passed type parameter or Key ancestor is not provided. Therefore, it will always return a `T?` type. If the value you inject is not required to be provided, you can use `??` to set a default value:

```dart
final String message = inject(context) ?? 'This is the default message';
```
