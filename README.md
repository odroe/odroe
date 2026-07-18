# Odroe

Odroe 是面向 Flutter 应用的全栈元框架。应用最终构建 Android、iOS、Web、桌面端还是其他 Flutter 目标，由应用自己决定；Odroe 不把产品限定为 Flutter Web，也不要求第二套前端。

仓库采用单一 `odroe` package，以产品能力划分入口：

- `package:odroe/odroe.dart`：标准 Odroe Flutter App 入口，组合 Router、Query 与 Start handoff；
- `package:odroe/router.dart`：可独立使用的强类型 Router；
- `package:odroe/router_core.dart`：供共享 `route.dart` 与 Dart VM 使用的平台中立契约；
- `package:odroe/router_compiler.dart`：`routes/` 文件路由编译器；
- `package:odroe/query.dart`：Query core 与 Flutter bindings；
- `package:odroe/query_core.dart`：平台中立的 server-state、mutation、hydration 与 persistence；
- `package:odroe/start.dart`：adapter-neutral Start runtime、Server Function/Route、middleware、serialization 与首屏 handoff；
- `package:odroe/start_flutter.dart`：Start 浏览器 handoff 与标准 Flutter bootstrap；
- `package:odroe/start_io.dart`：默认 Dart IO host adapter。

## 创建应用

先用 Flutter CLI 创建标准应用，再加入 Odroe：

```sh
flutter create my_app
cd my_app
flutter pub add odroe
```

建立目录路由：

```text
lib/
├── main.dart
└── routes/
    ├── shell.dart
    ├── page.dart
    └── posts/
        └── [postId]/
            ├── route.dart
            ├── page.dart
            └── server.dart
```

生成 client 与 server 两个 route target：

```sh
dart run odroe generate
```

正常开发直接运行：

```sh
dart run odroe dev
dart run odroe dev -- -d macos
```

Flutter target 始终由用户或 Flutter CLI 选择；Odroe 不默认 Web。

标准 Odroe App 入口直接使用生成的 route tree。它会创建同一个 Router/Query runtime，并在 Web 上自动消费 Start 首屏 handoff：

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

void main() => runOdroeApp(
  routes: routeTree,
  builder: (app) => MaterialApp.router(routerConfig: app.router),
);
```

只需要 Router 时仍可直接使用 `OdroeRouter`，不必采用 Start 或标准 bootstrap。

当前 Start Web 链路提供服务端 HTML shell、首屏 loader/Query 状态、流式 Query frame、Flutter 静态资源与客户端接管；它还没有把 Flutter widget tree 渲染为可见 HTML，也尚未提供 SSG 命令，因此当前版本不能宣称完整 SSR/SSG。

## 路由文件

`route.dart` 只声明客户端与服务端共享的强类型契约，因此使用不依赖 `dart:ui` 的 core 入口：

```dart
import 'package:odroe/router_core.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview});

final route = AppRoute<Params, Search, NoData>(
  params: const PathParams<Params>.schema(),
  search: const SearchParams<Search>.schema(
    defaults: (preview: false),
  ),
);
```

`page.dart` 只负责 Flutter 页面：

```dart
import 'package:flutter/widgets.dart';
import 'package:odroe/router.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Text('Post ${context.params.postId}'),
);
```

生成的 `routes` 是强类型绝对引用。祖先 params 会合并，祖先 search 保留明确的 route ownership：

```dart
context.router.go(
  routes.posts.postId.to(
    params: (postId: 42),
    postsSearch: (sort: 'newest'),
    search: (preview: true),
  ),
);
```

## 独立手动组装

文件路由不是独立 runtime。手动路由与生成路由都使用 `AppRoute`、`RouteMatcher`、`RouteRef`、`Destination` 和 `OdroeRouter`。

嵌套路由通过强类型 `RouteRef` 组合完整地址：

```dart
final destination = organization
    .ref(params: (organizationId: 'odroe'))
    .then(project.ref(params: (projectId: 7)))
    .destination;
```

完整文件规范、params/search 规则、shell、loader 与导航 API 见 [Router 文档](doc/router.md)。Query 的请求去重、Flutter binding、mutation、infinite query 和 hydration 见 [Query 文档](doc/query.md)。Start 的 RPC、公开 HTTP route、middleware、serialization、streaming、handoff 与 CLI 见 [Start 文档](doc/start.md)。可运行全链路应用见 [`example/router_app`](example/router_app)。
