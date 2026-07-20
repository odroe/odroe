# Odroe

Odroe 是单包、可组合的 Flutter 全栈元框架。Flutter 构建 Android、iOS、Web、桌面或其他目标；只有应用选择 Web 时，Document 的 SSR/SSG 与 Flutter 首屏交接才参与构建。

Odroe 不提供一个暗中装配全部能力的全局对象。应用显式选择 modules；Router、Query、Document、RPC 与 Server 也都能独立导入。

## 入口

| 入口 | 能力 |
| --- | --- |
| `odroe.dart` | 平台中立的 `Module`、binding、`AppContext` 与生命周期 |
| `odroe_flutter.dart` | Flutter `App` 组合根与 Flutter binding |
| `query.dart` | 平台中立的 Query、Mutation、cache、hydration 与 persistence |
| `query_flutter.dart` | Query Flutter provider、builders 与 `QueryModule` |
| `router.dart` | 基于 Roux 的中立强类型 route、params/search、matching 与 URL 生成 |
| `router_flutter.dart` | `PageRoute`、`ShellRoute`、`AppRouter` 与 `RouterModule` |
| `document.dart` | 语义 HTML、metadata、SEO/GEO、SSR/SSG renderer |
| `document_flutter.dart` | Flutter Web 首屏 handoff 与 `DocumentModule` |
| `rpc.dart` | 强类型 server functions、client、transport 与 `RpcModule` |
| `server.dart` | adapter-neutral HTTP、middleware、route 与 `Server` |
| `server_io.dart` | Dart IO host 与 prerenderer |

无后缀入口与 `lib/src/<capability>/` 都是平台中立实现；Flutter 代码只存在于 `<capability>_flutter`，Dart IO 代码只存在于 `server_io`。

## 创建应用

```sh
flutter create my_app
cd my_app
flutter pub add odroe
```

```text
lib/
├── main.dart
├── routes/
│   ├── route.dart
│   ├── shell.dart
│   ├── page.dart
│   └── posts/
│       └── [postId]/
│           ├── route.dart
│           ├── page.dart
│           └── server.dart
├── routes.dart          # generated client tree
└── routes.server.dart   # generated server tree
```

每个包含 `page.dart`、`shell.dart` 或 `server.dart` 的目录必须包含自己的中立 `route.dart`。没有 flat-route 语法、annotation、`part`、build_runner、registry 或 hash 清单。

## 组合应用

```dart
import 'package:flutter/material.dart';
import 'package:odroe/document_flutter.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import 'routes.dart';

void main() {
  runApp(
    App(
      modules: <Module>[
        QueryModule(),
        RpcModule.http(),
        DocumentModule(),
        RouterModule(routes: routeTree),
      ],
      builder: (app) => MaterialApp.router(
        routerConfig: app.read(routerKey),
      ),
    ),
  );
}
```

删掉任意 module 就会删掉对应集成；`odroe.dart` 本身不创建 Query、Router、RPC、Provider 或 transport。独立使用 Router 时也可以直接创建 `AppRouter(routes: ...)`。

Web 可让 `RpcModule.http()` 使用当前 origin；Android、iOS 与桌面应用应传入明确的服务端地址，例如 `RpcModule.http(baseUri: Uri.parse('https://api.example.com'))`。

## 文件路由

`route.dart` 只声明跨平台的强类型合同与 metadata。Document 是导入 `document.dart` 后附加的可选能力，不是 `AppRoute` 核心参数。

```dart
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview});

final route =
    AppRoute<Params, Search, NoData>(
      metadata: const RouteMetadata(description: 'Readable post content.'),
      params: const PathParams<Params>.schema(),
      search: const SearchParams<Search>.schema(
        defaults: (preview: false),
      ),
    ).document(
      (context) => RouteDocument(
        title: 'Post ${context.params.postId}',
        body: HtmlElement(
          'h1',
          children: <HtmlNode>[
            HtmlText('Post ${context.params.postId}'),
          ],
        ),
      ),
    );
```

`page.dart` 只绑定 Flutter 客户端行为：

```dart
import 'package:flutter/widgets.dart';
import 'package:odroe/router_flutter.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Text('Post ${context.params.postId}'),
);
```

`server.dart` 只绑定服务端 loader、HTTP handler 与 server functions：

```dart
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  load: (_) => const NoData(),
  handlers: <HttpMethod, ServerRouteHandler<definition.Params, definition.Search>>{
    HttpMethod.get: (context) => ServerResponse.json(
      <String, Object?>{'postId': context.params.postId},
    ),
  },
);

final updatePost = ServerFunction<int, bool>(
  handler: (context) async => repository.update(context.data),
);
```

文件名只有一种心智：`definition.route.page(...)`、`definition.route.shell(...)`、`definition.route.server(...)`、`definition.route.document(...)`。

## 服务端组合

生成的 `routes.server.dart` 暴露 `createServer(modules: ...)`。需要全局 middleware、request-scoped Query 或自定义 renderer 时，创建应用级 `lib/server.dart`；CLI 会自动把它作为 server 入口：

```dart
import 'package:odroe/query.dart';
import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() => generated.createServer(
  modules: () => <QueryClientModule>[QueryClientModule.server()],
);
```

loader、middleware 与 server function 都可以通过 `context.read(queryClientKey)` 读取该请求显式安装的 Query client。没有 `lib/server.dart` 时，CLI 直接使用生成的默认 server。

## CLI

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
dart run odroe dev -- -d ios
dart run odroe dev -- -d chrome
dart run odroe build apk
dart run odroe build web
```

`dev` 不默认 Web；`--` 后参数原样交给 Flutter CLI。`build web` 会构建 Flutter Web 与 server artifact，再通过真实 server prerender 静态 route。纯 Document route 输出纯 HTML；带 Flutter page 的 route 输出可读语义 HTML、handoff state 与原样 `/flutter_bootstrap.js`，随后由已加载的 Flutter app 承接导航。

可运行应用见 [`example/app`](example/app)。官网与正式文档将由 Odroe 自身构建在 `sites/odroe.dev`，仓库不提交研究过程文档。
