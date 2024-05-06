# Odroe

[![Pub Version](https://img.shields.io/pub/v/odroe)](https://pub.dev/packages/odroe)
[![GitHub License](https://img.shields.io/github/license/odroe/odroe)](https://github.com/odroe/odroe/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-odroe.dev-brightgreen)](https://odroe.dev/)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/medz?label=github%20sponsors)](https://github.com/sponsors/medz)
[![Open Collective sponsors](https://img.shields.io/opencollective/sponsors/openodroe?label=open%20collective)](https://opencollective.com/openodroe)
[![Discord](https://img.shields.io/discord/1035043284457881620?label=discord)](https://discord.gg/ms2X9TQMR8)
[![X (formerly Twitter) Follow](https://img.shields.io/twitter/follow/shiweidu)
](https://twitter.com/shiweidu)

Odroe is a declarative Flutter UI framework used to create user interfaces. It is built on top of Flutter and updated with fine-grained reactions. Declare your state and use it throughout the entire application, and only code that depends on it will rerun when the state changes.

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget counter() => setup(() {
    final count = $state(0);

    void increment() => count.update((value) => value + 1);

    return TextButton(
        onPressed: increment,
        child: Text('Count: ${count.get()}'),
    );
});
```

## Features

- **Compatibility**, Setup Widget is fully compatible with Flutter Class WIdget and can be used with each other.
- **Refined**, the amount of code is significantly reduced compared to Class Widget.
- **Reactive**, your state has reactive primitives, which are based on the Signal design.
- **Simple**, Setup Widget is a typical functional widget, learn some powerful concepts of composition, reusability and construction.

## Why Odroe

Odroe adopts functional Widget design (we call it Setup Widget), which draws on years of experience in building web front-end frameworks to make it easier for you to write Widgets.
