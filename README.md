# Odroe

Odroe 是单包的 Flutter 全栈元框架。Flutter 最终构建 Android、iOS、Web、桌面端或其他目标，由应用与 Flutter CLI 决定；Web 只是其中一个目标。

## 入口

- `package:odroe/odroe.dart`：完整 Odroe Flutter App，直接提供 Router、Query、RPC、服务端合同与首屏交接。
- `package:odroe/query.dart`：平台中立的 Query 状态机、cache、mutation、hydration 与 persistence。
- `package:odroe/query_flutter.dart`：`query.dart` 加 Flutter provider、builder 与 selector。
- `package:odroe/route.dart`：平台中立的强类型 route、params/search codec、matcher 与 document contract。
- `package:odroe/router.dart`：`route.dart` 加 Flutter Router、page 与 shell。
- `package:odroe/document.dart`：语义 HTML、SEO/GEO document 与 renderer。
- `package:odroe/rpc.dart`：可独立使用的强类型 RPC client、ref、transport 与 serializer。
- `package:odroe/server.dart`：adapter-neutral server、middleware、RPC implementation 与公开 HTTP route。
- `package:odroe/server_io.dart`：Dart IO host 与 SSG prerenderer。

文件路由编译器由 CLI 内部使用，不是公开入口。每项能力都可以单独导入；`odroe.dart` 是标准完整应用入口。

## 创建应用

先创建标准 Flutter App，再加入 Odroe：

```sh
flutter create my_app
cd my_app
flutter pub add odroe
```

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

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev -- -d macos
dart run odroe dev -- -d chrome
```

`dev` 不默认 Web；`--` 后的参数原样交给 Flutter CLI。

## 四个用户文件

### `main.dart`

完整应用只导入 `odroe.dart`。`OdroeApp` 直接持有 `query`、`router` 与 `rpc`：

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

void main() => runOdroeApp(
  routes: routeTree,
  builder: (app) => MaterialApp.router(
    routerConfig: app.router,
  ),
);
```

Web RPC 默认使用当前页面的同源地址。Android、iOS 与桌面 App 没有浏览器 origin，应显式传入服务端地址：

```dart
runOdroeApp(
  routes: routeTree,
  server: Uri.parse('https://api.example.com'),
  builder: (app) => MaterialApp.router(routerConfig: app.router),
);
```

任意 descendant widget 可通过 `OdroeApp.of(context)` 读取同一个应用对象。需要自定义生命周期时可调用 `createOdroeApp`，并在结束时执行 `dispose()`。

### `route.dart`

共享合同只导入平台中立的 `route.dart`：

```dart
import 'package:odroe/route.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview});

final route = AppRoute<Params, Search, NoData>(
  params: const PathParams<Params>.schema(),
  search: const SearchParams<Search>.schema(
    defaults: (preview: false),
  ),
  document: (context) => RouteDocument(
    title: 'Post ${context.params.postId}',
    body: HtmlElement(
      'h1',
      children: <HtmlNode>[HtmlText('Post ${context.params.postId}')],
    ),
  ),
);
```

`RouteDocument` 是纯 HTML route 的页面，也是 Flutter route 的 SEO/GEO 可读内容；它不是第二套 Flutter UI。

### `page.dart`

Flutter 页面只导入 `router.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:odroe/router.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Text('Post ${context.params.postId}'),
);
```

### `server.dart`

服务端实现导入 `server.dart`；需要共享 route 类型时同时导入 `route.dart`：

```dart
import 'package:odroe/route.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  load: (context) => const NoData(),
  handlers: {
    HttpMethod.get: (context) => ServerResponse.json(
      <String, Object?>{'postId': context.params.postId},
    ),
  },
);

final updatePost = ServerFunction<int, bool>(
  handler: (context) async => repository.update(context.data),
);
```

`server.dart` 不会进入 Flutter client 产物。CLI 生成 client-safe `lib/routes.dart`、server-only `lib/routes.server.dart` 与 typed RPC refs；用户不维护 registry、hash 文件、annotation、`part` 或 build_runner。

## SSR 与 SSG

Web 首次请求由 Odroe server 输出语义 HTML、metadata、loader/Query state 与可选 Flutter bootstrap。Flutter 第一帧后接管可见界面，后续导航由已经加载的 Flutter Router 处理。纯 Document route 不加载 Flutter。

```sh
dart run odroe build -- web --release
```

Web 构建会请求真实 server 生成静态 HTML；静态 route 自动生成，站内链接可发现动态 route。没有 `page.dart` 或 `shell.dart` 的应用可直接生成纯 HTML。`public/` 原样复制，Odroe 不生成站点 CSS。

完整规范见 [Router](doc/router.md)、[Query](doc/query.md) 与 [Server、RPC、SSR/SSG](doc/server.md)。可运行应用见 [`example/app`](example/app)。
