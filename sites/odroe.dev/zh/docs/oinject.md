---
title: Oinject → 快速开始
description: Oinject 是一个简单而强大的依赖注入包，使一个祖先组件作为其后代组件的依赖注入方，无论这个组件的层级有多深都可以注入成功，只要他们处于同一条组件链上。
---

通常情况下，当我们需要从父 Widget 向子 Widget 传递数据是，我们会使用 Widget 构造参数。但通常，我们的 Widget 结构是多层嵌套
的，形成一颗巨大的 Widget Tree。而某一个较深层级的子 Widget 需要一个较远的祖先 Widget 中的部分数据。
在这种情况下，仅仅使用构造参数沿着 Widget 链逐级向下传递就会非常麻烦。

::: tip
我们可以阅读 [Flutter 简易状态管理 - 提高状态层级](https://docs.flutter.dev/data-and-backend/state-mgmt/simple#lifting-state-up) 了解它的重要性。
:::

## 为什么需要 Oinject？

在 Flutter 生态中，又非常多的包可以做到类似的事情，例如 [Provider](https://pub.dev/packages/provider)。甚至 Flutter 本身就带有
简易的数据提供方式 [InheritedWidget](https://api.flutter.dev/flutter/widgets/InheritedWidget-class.html)。

而 Oinject 的优势在于非常少的样板代码、简单易用，这是一份简单的对比：

| 名称 | 样板代码 | Widget 树污染 | 支持数据堆叠 |
|-----|----|----|----|
| `provider` | 一般 | 污染 | 不支持 |
| InheritedWidget | 多 | 污染 | 不支持 |
| `oinject` | 少 | 不 | 支持 |

最重要的一点，Oinject 完全可以和任何 Widget 进行配合（只要它拥有 `BuildContext`)。这为你已有 App 向 Onject 迁移提供了极大的便利。

## 安装

我们运行下面的命令：

```bash
flutter pub add oinject
```

或者在你的 `pubspace.yaml` 中添加：

```yaml
dependencies:
  oinject: latest
```

## Provide（提供）

要向 Widget 后代提供数据，需要使用到 `provide()` 函数：

```dart
class MyWidget extends StatelessWidget {
    Widget build(BuildContext context) {
        provide(context, 'value');

        return ...;
    }
}
```

`provide()` 函数接受三个值和一个类型参数。第一个参数是 Flutter Widgets 的构建上下文（被称为 `BuildContext`, 通常我们使用 `context` 接收）。
第二个参数是具体需要提供的值，它与类型参数相匹配（伪代码：`<T>(T value)`)。第三个参数是用于数据堆叠的类型数据 Key，它被设计为 Symbol 类型：

```dart
provide(context, 'value', key: #hello);
```

Key 的最大用处莫过，准确的标注数据（依靠类型参数并不可靠）、或者进行不同类型数据的数据堆叠：

```dart
provide(context, key: #user, 1);
provide(context, key: #user, 'Seven');
```

由此，我们可以简单的想后代传递 User 的 ID 和 Name。（仅适用于类型并不冲突的类型数据）

## 全局的 Provide

除了在 Widget 树中进行数据提供，也许你也希望在 Flutter 应用入口进行全局的数据提供。我们需要用到 `provide.global()` 函数：

```dart
void main() {
    provide.global('value');

    runApp(const App());
}
```

`provide.global()` 与 `provide` 的唯一区别在于全局提供不需要 `BuildContext` 参数。它只有两个参数，分别对应 `provide()` 的
第二和第三参数：

```dart
void main() {
    provide.global(key: #user, 1);
    provide.global(key: #user, 'name');

    runApp(const App());
}
```

## Inject（注入）

要注入上层 Widget 提供的数据，需使用 `inject` 函数：

```dart
class ChildWidget extends StatelessWidget {
    Widget build(BuildContext context) {
        final name = inject<String>(context);

        return ...;
    }
}
```

带有 Key 的注入：

```dart
final id = inject<int>(context, #user);
final name = inject<String>(context, #user);
```

### 默认注入值

默认情况下，`inject()` 假设传入的类型参数或者 Key 祖先并未提供。因此，它始终会返回 `T?` 类型。
如果你注入的值不要求必须提供，可以使用 `??` 设置默认值：

```dart
final String message = inject(context) ?? '这是默认消息';
```
