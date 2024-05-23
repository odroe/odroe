---
title: Lifecycle
titleTemplate: :title · Essentials with Odroe
---

# {{ $frontmatter.title }}

Each Widget will need to go through a series of initialization steps after use, such as Signal listening, mounting the Widget instance to Element, etc., and updating the widget when data changes. Along the way, it also runs functions called lifecycle hooks, giving developers the opportunity to run their own code at specific stages.

## Registration cycle hook

For example, the onMounted hook can be used to run code after the Widget has completed its initial rendering and created the Element node:

```dart
setup(() (
     onMounted(() {
         print('The setup-widget is now mounted.');
     });

     return () => ...; // Define a widget render.
));
```

There are other hooks that will be called at different stages of the instance life cycle, the most commonly used are `onMounted`, `onUpdated`, and `onUnmounted`.

## Lifecycle hooks

- `onMounted`: Register a callback function to be executed after the Setup-widget is mounted.
- `onUpdated`: Register a callback function, which will be executed after the Setup-widget's Props are updated.
- `onUnmounted`: Register a callback function to be called after the Setup-widget instance is unmounted.
- `onBeforeUpdate`: Register a callback function to be executed before the Setup-widget's Props are updated.
- `onBeforeUnmount`: Register a hook to be called before the Setup-widget instance is unmounted.
- `onActivated`: Register a callback function, if the Setup-widget instance is part of the keep alive cache tree, it will be called when the Setup-widget is activated.
- `onDeactivated`: Register a callback function, if the Setup-widget instance is part of the keep alive cache tree, it will be called when the Setup-widget is removed.
