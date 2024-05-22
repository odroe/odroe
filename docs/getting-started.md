---
title: Getting Started
titleTemplate: :title · Introduction with Odroe
description: Odroe's goal is to make Flutter development intuitive and performant with a great Developer Experience in mind.
---

# {{ $frontmatter.title }}

{{ $frontmatter.description }}

[[toc]]

## Installation

### Depend on it

Run this command(with Flutter):

```bash
flutter pub add odroe
```

This will add a line like this to your package's `pubspec.yaml` (and run an implicit `flutter pub get`):

<script setup lang="ts">
import { data } from '../pubspec.data.ts';

const version = data.filter(p => p.name === 'odroe').pop().version;
</script>

```yaml-vue
dependencies:
  odroe: ^{{ version }}
```

### Import it

Now in your Dart code, you can use:

```dart
import 'package:odroe/odroe.dart';
```

## Create and nesting Setup-widget

The Odroe setup widget consists of functions, which are passed internally through 'setup' and then return a `Widget Function()` to render Widgets:

```dart
hello() => setup(() {
    return () => const Text('Hi, I\'m Odroe!');
});
```

Now that the `hello` setup-widget has been declared, we can nest it into other setup-widgets or Flutter widgets:

```dart
app() => setup(() {
    return () => MaterialApp(
        title: 'Odroe',
        home: hello(),
    );
});
```
