# Odroe

Odroe 是面向 Flutter 应用的全栈元框架。应用最终构建 Android、iOS、Web、桌面端还是其他 Flutter 目标，由应用自己决定；Odroe 不把产品限定为 Flutter Web，也不要求第二套前端。

仓库采用单一 `odroe` package，以产品能力划分入口。当前完成的第一个产品是 Router：

- `package:odroe/router.dart`：可独立使用的强类型 Router；
- `package:odroe/router_core.dart`：供共享 `route.dart` 与 Dart VM 使用的平台中立契约；
- `package:odroe/router_compiler.dart`：`routes/` 文件路由编译器；
- `package:odroe/start.dart`：服务端 route fragment 的边界；Start 的 HTTP/RPC runtime 后续实现。

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

编译路由：

```sh
dart run odroe routes
```

开发时持续编译：

```sh
dart run odroe routes --watch
```

在应用入口使用生成的普通 route tree：

```dart
import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

import 'routes.dart';

final router = OdroeRouter(routes: routeTree);

void main() => runApp(
  MaterialApp.router(routerConfig: router),
);
```

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

完整文件规范、params/search 规则、shell、loader 与导航 API 见 [Router 文档](doc/router.md)。可运行应用见 [`example/router_app`](example/router_app)。
