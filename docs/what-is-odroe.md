---
title: What's Odroe?
titleTemplate: :title · Introduction with Odroe
description: Odroe is an extension pattern framework on top of the Flutter framework that allows you to create widgets using functions (we call them Setup-widget).
---

# {{ $frontmatter.title }}

{{ $frontmatter.description }}

## Why Odroe?

Odroe utilizes functional widget creation and is designed for Flutter Apps development, eliminating the need to decide between `StatelessWidget` and `StatefulWidget`. It also eliminates the need to add `const` to your widgets for performance improvement.

Odroe's code for declaring a widget is typically half the size of a class-widget, resulting in less code and more value.

## Features

- **Compatibility:** Setup-widgets can be used interchangeably with Flutter widgets.
- **Conciseness:** Less code compared to class-widgets.
- **Signal:** Leveraging years of experience from frameworks like React/Vue/Svelte, Signal provides a richer state management and data sharing approach throughout Setup-widgets.
- **Compositional:** Setup-widgets are typical functional widgets, encouraging the learning of powerful composition, reusability, and construction concepts.

## Development Experience

Utilize multiple closures to intuitively grasp the order of operation and lifecycle management of widgets. Everything unfolds naturally, using declarative function statements to register your logic. Or, effortlessly reuse state logic through composition.

## What Else is Odroe?

Inspired by Vue and Preact, Odroe initially aimed to simply write functional widgets in Flutter.

Odroe implements functional widgets using Flutter Element and wraps them with a `setup` function. Inside `setup`, you can write your logic and state, or utilize other compositional functions.
