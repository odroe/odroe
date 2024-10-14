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
| oref_flutter | [![Pub Version](https://img.shields.io/pub/v/oref_flutter)](https://pub.dev/packages/oref_flutter) | Oref 与 Flutter 的集成 |

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
