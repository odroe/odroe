---
title: Functional Widget
titleTemplate: :title · Essentials with Odroe
---

# {{ $frontmatter.title }}

A function will wrap the `setup` function, process any parameters you pass in, and return a standard Flutter widget.

```dart
myWidget() => setup(() {
    return () => const Text('My first setup-widget.');
});
```

## Using Props

You can declare function parameters like any Dart function:

```dart
say(String name) => setup(() {
    return () => Text('Hello, $name');
});
```

This is fine for setup-widgets that don't need to update the `name` parameter, but it won't work if we need to re-render the Text widget based on the `name` parameter passed from the parent widget.

You should convert `name` to a Signal prop:

```dart
Widget say(String name) {
    defineProps([name]);

    return setup(() {
        final [name] = props();

        return () => Text('Hello, ${name.value}');
    });
}
```

Use `defineProps` to declare your props and use the `props()` function inside `setup` to receive them. Internally, we will convert external props to signals.

### Why do we do this?

The function inside `setup` is only executed once during the mount phase, so you cannot directly handle subsequent updates to the function parameter values inside the `setup` function.

## Setting `Key` for widget

We have a niche requirement that in Flutter we can assign a `Key` to a widget to mark whether it needs to be rebuilt. In functional widgets, we use `defineKey` to define it.

```dart
hello() {
    defineKey(...);

    return setup(() {
        ...

        return () => ...;
    });
}
```

## `BuildContext`

In Flutter, we often need to use `BuildContext`, although in Setup-widget we rarely use it. But you still need to use it for class-widget requirements, such as the Theme or navigator of Flutter m3 UI.

We provide the `useContext()` hook to get it:

```dart
myWidget() => setup(() {
    final context = useContext();

    return () => ...;
});
```
