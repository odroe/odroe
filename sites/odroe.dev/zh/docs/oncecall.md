---
title: 文档 → 记忆化（Oncecall）
description: Oncecall 是一个适用于 Flutter Widget build 方法的记忆化工具。允许你的代码在 build 方法中仅调用一次，即使 Widget 重建也不会丢失。
head:
  - - meta
    - property: og:title
      content: Odroe | 文档 → 记忆化（Oncecall）
prev: false
next: false
---

{{ $frontmatter.description }}

## 为什么需要它？

我们总是想构造一些具有动态属性又符合 `const` Widget 的用例，或者我们有一些逻辑必须放在 `build` 方法中。

而 Oncecall 允许你在 `build` 中编写仅运行一次的代码。

## 安装

我们使用下面的命令：

```bash
flutter pub add oncecall
```

或在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  oncecall: latest
```

## 基本用法

```dart
class MyWidget extends StatelessWidget {
    const MyWidget({super.key});

    Widget build(BuildContext context) {
        oncecall(context, () => print('只会运行一次'));

        return ...;
    }
}
```

这看起来似乎没有什么不同。但如果没有 oncecall，你将编写下面的代码：

```dart
class MyWidget extends StatelessWidget {
    MyWidget({super.key}) {
        print('只会运行一次'); // Widget 重建也许会再次执行
    }

    Widget build(BuildContext context) {
        return ...;
    }
}
```

## 用于一次性计算

`oncecall()` 函数除了用于运行一次性函数之外，它还可以进行一些对象的初始化工作：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    Widget build(BuildContext context) {
        final value = oncecall(context, () {
            ...
        });

        return ...;
    }
}
```

## 更多

Oncecall 作为 Odroe 生态的基础建设，你会在其他包中无处不在地看到它。它是一个非常低级且简单的 API，和它的名字一样仅仅用于依赖于 context 进行值的记忆化和初始化工作。
