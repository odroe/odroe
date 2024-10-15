---
title: 文档 → Oref → 介绍
description: Dart/Flutter 低入侵性的响应式系统。
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → Dart/Flutter 低入侵性的响应式系统。
prev: false
---

{{ $frontmatter.description }}

在许多框架中类似的响应性基础类型被称之为 "信号"，从根本上来讲，Oref 是与信号概念一样拥有相同的响应性基础类型。
它是一个在访问时跟踪依赖、在变更时触发副作用的值容器。

## 什么是响应性？ {#what-is-reactivity}

本质上响应性是一种可以使我们声明式地处理变化的编程范式。有太多的前端框架都在讲述它的重要性：

- [Preact.js Signals](https://preactjs.com/blog/introducing-signals/)
- [Vue.js 深入响应式系统](https://cn.vuejs.org/guide/extras/reactivity-in-depth.html#what-is-reactivity)
- [Solid 信号](https://www.solidjs.com/docs/latest/api#createsignal)
- [Dart: `signals` package](https://dartsignals.dev/reference/overview)

## 安装 {#installation}

你可以直接将 Oref 通过这个命令添加到任何 Dart 项目中：

```bash
dart pub add oref
```

或者修改你的 `pubspec.yaml` 文件：

```yaml
dependencies:
  oref: latest
```

## 基本用法 {#basic-usage}

```dart
import 'package:oref/oref.dart';

void main() {
  final count = ref(0);
  final double = derived(() => count.value * 2);
  final runner = effect(() {
    print('count: ${count.value}, double: ${double.value}');
  }, onStop: () {
    print('effect stopped');
  });

  count.value = 10; // 打印 'count: 10, double: 20'

  // 停止 effect
  runner.effect.stop(); // 打印 'effect stopped'

  count.value = 20; // 无效

  // 如果 effect 被停止，我们可以手动运行一次。
  runner(); // 打印 'count: 20, double: 40'

  count.value = 30; // 无效
}
```
