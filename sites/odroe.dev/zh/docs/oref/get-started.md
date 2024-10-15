---
title: 文档 → Oref → 快速开始
description: Oref 在 Dart/Flutter 中的安装与基本使用指南
head:
  - - meta
    - property: og:title
      content: Odroe | Oref 在 Dart/Flutter 中的安装与基本使用指南
---

{{ $frontmatter.description }}

## 安装

Oref 提供两个包：

| 名称 | 版本 | 描述 |
|----|----|----|
| `oref` | [![Pub Version](https://img.shields.io/pub/v/oref)](https://pub.dev/packages/oref) | 响应式核心 |
| `oref_flutter` | [![Pub Version](https://img.shields.io/pub/v/oref_flutter)](https://pub.dev/packages/oref_flutter) | Oref 与 Flutter 的集成 |

我们使用下面命令进行安装：

::: code-group

```bash [Dart 项目]
dart pub add oref
```
```bash [Flutter]
flutter pub add oref_flutter
```
:::

或者更新你的 `pubspec.yaml` 文件：

::: code-group
```yaml [Dart 项目]
dependencies:
  oref: latest
```
```yaml [Flutter]
dependencies:
  oref_flutter: latest
```
:::

## 声明响应式状态

要声明一个响应式状态，我们使用 `ref()` 函数

::: code-group
```dart [Dart]
final count = ref(0)
```
```dart [Flutter]
final count = ref(context, 0)
```
:::

`ref()` 接收参数，并返回一个包裹带有 `.value` 属性的 `Ref<T>` 对象：

::: code-group
```dart [Dart]
void main() {
    final count = ref(0);

    print(count); // Ref<int>
    print(count.value); // 0

    count.value++;
    print(count.value); // 1
}
```
```dart [Flutter]
class MyWidget extends StatelessWidget {
    const MyWidget({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0); // [!code focus]

        return TextButton(
            onPressed: () => count.value++, // [!code focus]
            child: Text('Count: ${count.value}'), // [!code focus]
        );
    }
}
```
:::

## 声明响应式集合

::: tip WIP
正在开发中，请阅读我们的[路线图](https://github.com/odroe/odroe/issues/17)。
:::

## 细粒度重建 <Badge type="tip" text="Flutter" />

例如 [声明响应式状态](#声明响应式状态) 例子中的 Counter 代码，当我们更新 `count` 的值的时候，整个 `Counter` Widget 都会重建。
这是没有意义的，因为我们只需要 `Text` 重建即可。

推荐使用 `Observer` Widget 来进行优化：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: Observer( // [!code focus]
                builder: (_) => Text('Count: ${count.value}'), // [!code focus]
            ), // [!code focus]
        );
    }
}
```

当 `count` 内部值更新的时候，就只会重建 `Text` 了。
不过 `Observer` 适合用于收集多个响应性值，对于简单的使用我们推荐 `obs()` 函数：

```dart
class Counter extends StatelessWidget {
    const Counter({super.key});

    @override
    Widget build(BuildContext context) {
        final count = ref(context, 0);

        return TextButton(
            onPressed: () => count.value++,
            child: count.obs((value) => Text('Count: ${value}')), // [!code focus]
        );
    }
}
```

> [!TIP]
> 有关 `obs()` 更多细节，请查看[核心 → 可观测](/zh/docs/oref/core#可观测-obs)。

对于细粒度重建可以有多种实现方式：

* 使用 `Observer` 包装观测响应性数据
* 使用 [`obs()`](/zh/docs/oref/core#可观测-obs) 进行观测。
* 使用 [`derived() - 派生`](/zh/docs/oref/core#派生-derived) 将值进行组合。
