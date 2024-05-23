---
title: Composables
titleTemplate: :title · Essentials with Odroe
---

# {{ $frontmatter.title }}

In Odroe's Setup-widget concept, "Composables" are functions that leverage Signal and lifecycle hooks and reuse **stateful logic**.

When building Flutter Apps, we often need to reuse logic for common tasks. For example, in order to format time in different places, we might extract a reusable date formatting function. This function encapsulates stateless logic: it takes some input and returns the desired output immediately.

In contrast, stateful logic manages state that changes over time. A simple example is tracking the current mouse position on the page. In a real application, it could also be more complex logic like touch gestures or connection status to a database.

## Counter example

If we use Signal directly in the Widget to count, it will look like this:

```dart
counter() => setup(() {
     final count = signal(0);

     return () => TextButton(
         onPressed: () => count.value++,
         child: Text('Count: ${count.value}'),
     );
});
```

But what if we want to reuse logic across multiple components? We can extract this logic to an external file or other location in the form of a combined function. Below, we use it in Setup-widget:

```dart
typedef UseCounterResult = (int Function() getter, void Function() increment);
UseCounterResult useCounter() {
     final count = signal(0);
     int getter() => count.value;
     void increment() => count.value++;

     return (getter, increment);
}

counter() => setup(() {
     final (count, increment) = useCounter();

     return () => TextButton(
         onPressed: increment,
         child: Text('Count: ${count()}'),
     );
});
```

As you can see, the core logic is exactly the same. All we do is move it from inside `setup` to an external function and return the status data and functions we need. As in Setup-widget, you can use all lifecycle hooks and signals in composed functions. Now the functionality of `useCounter` can be easily reused in any Setup-widget.

What’s even cooler is that you can use other composed functions within composed functions, just like you would in setup.
