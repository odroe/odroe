---
title: Signals
titleTemplate: :title · Essentials with Odroe
---

# {{ $frontmatter.title }}

Signals are a reactive primitive concept for managing application state.

Signals are unique in that state changes automatically update components and UI for the most efficient operation possible. Automatic state binding and dependency tracking allow Signals to provide excellent ergonomics and productivity while eliminating the most common state management pitfalls.

Signals are effective in applications of any size, the ergonomic design speeds the development of small applications, and the performance characteristics ensure that the default settings are fast in applications of any size.

## Introduction

A lot of the pain with state management in Flutter is reacting to changes in a given value, since the value itself is not directly observable. The usual solution is to solve this problem by storing the values in variables and constantly checking if they have changed, which is both tedious and bad for performance. Ideally, we'd like to have a way to express a value that tells us when something changed. That's what signals are for.

At its core concept, a signal is an object with a `.value` property that holds a value. This has an important property: the value of the signal can change, but the signal itself always remains the same.

```dart
import 'package:odroe/odroe.dart';

final count = signal(0);

// Read a signal’s value by accessing .value:
print(count.value) // 0

// Update a signal’s value:
count.value = 1;

// The signal's value has changed:
print(count.value); // 1
```

In Odroe, when signals are passed as props or context through the component tree, we only pass a reference to the signal. Signals can be updated without re-rendering any components because components see the signal and not its value. This lets us skip all the expensive rendering work and jump immediately to any component in the tree that actually accesses the signal's .value property.

Another important property of signals is that they track when their values are accessed and when they are updated. In Odroe, when the .value property of a signal is accessed from within the component, the component is automatically re-rendered when the signal's value changes.

```dart
Widget counter() => setup(() {
     final count = signal(0);

     void increment() => count.value++;

     return () => TextButton(
         onPressed: increment
         child: Text(count.value.toString())
     );
});
```

Of course, Signal can not only be used in Setup-widget, you can also declare signal anywhere. Below we create a global shared state counter:

```dart
final count = signal(0);

void increment() => count.value++;

counter() => setup(() {
     return () => TextButton(
         onPressed: increment
         child: Text(count.value.toString())
     );
});
```

No matter where you use counter, the click count state is always shared.

## `.peek()`

In the rare instance that you have an effect that should write to another signal based on the previous value, but you don't want the effect to be subscribed to that signal, you can read a signals's previous value via `signal.peek() `.

```dart
final counter = signal(0);
final effectCount = signal(0);

effect(() {
   print(counter.value);

   // Whenever this effect is triggered, increase `effectCount`.
   // But we don't want this signal to react to `effectCount`
   effectCount.value = effectCount.peek() + 1;
});
```

Note that you should only use `signal.peek()` if you really need it. Reading a signal’s value via `signal.value` is the preferred way in most scenarios.

## Computed

Data is often derived from other pieces of existing data. The `computed` function lets you combine the values of multiple signals into a new signal that can be reacted to, or even used by additional computeds. When the signals accessed from within a computed callback change, the computed callback is re-executed and its new return value becomes the computed signal's value.

> The `computed()` returns a `Readonly` class, `Readonly` extends `Signal` class.

```dart
final name = signal("Jane");
final surname = signal("Doe");

final fullName = computed(() => name.value + " " + surname.value);

// Logs: "Jane Doe"
print(fullName.value);

// Updates flow through computed, but only if someone
// subscribes to it. More on that later.
name.value = "John";
// Logs: "John Doe"
print(fullName.value);
```

## Effect

Run a function immediately while tracking its dependencies reactively and re-execute when dependencies change.

```dart
final count = signal(0);

effect(() => print(count.value)); // > 0

count.value++; // > 1
```

You can manually control when the listener is terminated:

```dart
final dispose = effect(() => ...);

dispose();
```

It is possible to return a function with the signature `void Function()` in `effect`, to be executed before `effect` stops listening:

```dart
effect(() {
     ...

     return () => ...;
});
```

## Untracked

In case when you’re receiving a callback that can read some signals, but you don’t want to subscribe to them, you can use `untracked` to prevent any subscriptions from happening.

```dart
final counter = signal(0);
final effectCount = signal(0);
final fn = () => effectCount.value + 1;

effect(() {
   print(counter.value);

   // Whenever this effect is triggered, run `fn` that gives new value
   effectCount.value = untracked(fn);
});
```

## Reactive

On top of Signal, Odroe builds reactive data. It is used to implement proxies for `List`/`Map`/`Set` data types, and you do not need to call `.value`.

- `reactive.map`: Create a Reactive `Map`.
- `reactive.list`: Create a Reactive `List`.
- `reactive.set`: Create a Reactive `Set`.

```dart
final profile = reactive.map({'name': 'Seven', age: 30});

effect(() => print(profile['age'])); // > 30

profile.age++; // > 31
```

## Batch

The `batch` function allows you to combine multiple signal writes into one single update that is triggered at the end when the callback completes.

```dart
final name = signal("Jane");
final surname = signal("Doe");
final fullName = computed(() => name.value + " " + surname.value);

// Logs: "Jane Doe"
effect(() => print(fullName.value));

// Combines both signal writes into one update. Once the callback
// returns the `effect` will trigger and we'll log "Foo Bar"
batch(() {
   name.value = "Foo";
   surname.value = "Bar";
});
```

When you access a signal that you wrote to earlier inside the callback, or access a computed signal that was invalidated by another signal, we’ll only update the necessary dependencies to get the current value for the signal you read from. All other invalidated signals will update at the end of the callback function.

```dart
final counter = signal(0);
final _double = computed(() => counter.value * 2);
final _triple = computed(() => counter.value * 3);

effect(() => print(_double.value, _triple.value));

batch(() {
   counter.value = 1;
   // Logs: 2, despite being inside batch, but `triple`
   // will only update once the callback is complete
   print(_double.value);
});
// Now we reached the end of the batch and call the effect
```

Batches can be nested and updates will be flushed when the outermost batch call completes.

```dart
final counter = signal(0);
effect(() => print(counter.value));

batch(() {
   batch(() {
     // Signal is invalidated, but update is not flushed because
     // we're still inside another batch
     counter.value = 1;
   });

   // Still not updated...
});
// Now the callback completed and we'll trigger the effect.
```

## Utilities

### `isSignal`

Checks whether a value is Signal.

```dart
if (isSignal(count)) {
     ...
}
```

### isReactive

Checks whether an object is a Reactive object.

```dart
if (isReactive(profile)) {
     ...
}
```
