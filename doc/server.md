# Server、RPC、SSR/SSG

Odroe 本身是完整 Flutter 全栈框架。服务端负责同一棵 route tree 的 loader、RPC、公开 HTTP route、Document 渲染与 Flutter 首屏交接；它不绑定数据库、ORM、HTTP server 或部署平台。

## 入口

- `package:odroe/odroe.dart`：标准完整 Flutter App，`OdroeApp` 直接提供 Query、Router 与 RPC。
- `package:odroe/rpc.dart`：独立 RPC client、typed ref、transport 与 serializer。
- `package:odroe/server.dart`：adapter-neutral request/response、middleware、server function、server route 与 `OdroeServer`。
- `package:odroe/server_io.dart`：Dart IO host 与构建期 prerenderer。

## 正常开发

```sh
# 生成 client-safe routes.dart 与 server-only routes.server.dart
dart run odroe generate

# 启动服务端和 Flutter；target 仍由 Flutter CLI 选择
dart run odroe dev
dart run odroe dev -- -d macos
dart run odroe dev -- -d chrome

# 只运行服务端
dart run odroe dev --server-only --port 3000

# 构建用户选择的 Flutter target
dart run odroe build apk
dart run odroe build -- web --release

# 只构建服务端 executable
dart run odroe build --server-only
```

`dev` 不默认 Web。route contract 或服务端实现变化时重新生成并重启服务端；普通 `page.dart` 变化仍由 Flutter hot reload 处理。

`generate` 产生：

- `lib/routes.dart`：Flutter/client-safe route tree、typed destination 与 RPC refs；
- `lib/routes.server.dart`：server route tree、function bindings 与 `createServer()`；
- `.dart_tool/odroe/server.dart`：默认 Dart IO bootstrap。

生成文件不使用 annotation、`part` 或 build_runner。用户的 route `server.dart` 不会被 client target 导入。

## Flutter 应用

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

void main() => runOdroeApp(
  routes: routeTree,
  builder: (app) => MaterialApp.router(routerConfig: app.router),
);
```

`OdroeApp` 直接提供：

- `app.query`：应用级 `QueryClient`；
- `app.router`：使用同一个 Query client 的 `OdroeRouter`；
- `app.rpc`：生成的 server-function ref 使用的 `RpcClient`。

任意 descendant widget 都可以通过 `OdroeApp.of(context)` 取得同一个对象，无需逐层传递。

Web 默认以 `Uri.base` 作为 RPC 地址，因此请求与页面同源。原生 Flutter App 应传入实际服务端 URI：

```dart
runOdroeApp(
  routes: routeTree,
  server: Uri.parse('https://api.example.com'),
  builder: (app) => MaterialApp.router(routerConfig: app.router),
);
```

也可以通过 `rpc`、`transport` 或 `serializer` 替换对应能力。需要自行持有与释放运行对象时使用 `createOdroeApp()`，结束时调用 `dispose()`。

## Route 的 `server.dart`

`server.dart` 复用同目录的共享 `route.dart`，并导出最终服务端 route：

```dart
import 'package:odroe/route.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  middleware: <Middleware>[requireSession],
  load: (context) => context.query.ensureQueryData(
    postQuery(context.params.postId),
  ),
  handlers: {
    HttpMethod.get: (context) => ServerResponse.json(
      <String, Object?>{'postId': context.params.postId},
    ),
  },
);
```

`server.dart` 还可以声明 App 内部 RPC：

```dart
final updatePost = ServerFunction<UpdatePostInput, bool>(
  middleware: <Middleware>[requireSession],
  handler: (context) async => repository.update(context.data),
);

final watchViews = ServerFunction<NoServerInput, Stream<int>>(
  handler: (_) => analytics.watchViews(),
);
```

Server Function 必须是公开、稳定的顶层变量。CLI 从文件路径和声明名生成内部 ID、server binding 与 client ref；用户不维护 ID、registry 或 hash 文件。

## RPC client

生成的 ref 位于 route facade。标准 Odroe App 直接使用 `app.rpc`：

```dart
final updated = await routes.posts.postId.updatePost.call(
  app.rpc,
  UpdatePostInput(title: 'Odroe'),
);

final stream = await routes.posts.postId.watchViews.call(
  app.rpc,
  const NoServerInput(),
);
await for (final views in stream) {
  // Stream<int>
}
```

独立使用 RPC 时导入 `rpc.dart`：

```dart
import 'package:odroe/rpc.dart';

final rpc = RpcClient(
  baseUri: Uri.parse('https://api.example.com'),
  transport: HttpTransport(),
);
```

普通值使用 `ServerFunctionRef<I, O>`，流使用 `ServerStreamFunctionRef<I, T>`。自定义环境只需实现 `RpcTransport`；协议不依赖 socket。

## Serialization

`Serializer` 支持 JSON-like value、递归 collection，以及 `DateTime`、`Duration`、`Uri`、`BigInt` 与 `Uint8List`。领域类型通过 `SerializationAdapter<T>` 扩展：

```dart
final serializer = Serializer(adapters: <SerializationAdapter<dynamic>>[
  PostIdAdapter(),
]);

final server = OdroeServer(
  routes: serverRouteTree,
  functions: serverFunctions,
  serializer: serializer,
);
```

编译器为可识别的 generic collection 生成 decoder。手动声明时可以分别提供 `ServerFunction.decodeInput` 与 `ServerFunctionRef.decodeOutput`。Serializer 只恢复 wire type；授权与领域校验仍属于 function 或 middleware。

## Middleware 与 HTTP

执行顺序是：全局 middleware → 父 route middleware → 子 route middleware → function/HTTP handler → 反向返回。

```dart
const sessionKey = ContextKey<Session>('session');

Future<ServerResponse> requireSession(
  RequestContext context,
  Next next,
) async {
  final session = await authenticate(context.request);
  context.set(sessionKey, session);
  return next();
}
```

每个请求拥有独立 `QueryClient`。RPC 默认拒绝跨源浏览器请求；只有构造 `OdroeServer(allowRpcWithoutOrigin: true, ...)` 时才允许缺少 origin metadata 的调用。

Server Function 与 Server Route 是不同入口：

- Server Function 是同一个 App 的 typed RPC，框架处理 serialization、错误、redirect、not-found 与 stream；
- Server Route 是公开 HTTP endpoint，适合 webhook、文件、第三方 API 与自定义协议，直接返回 `ServerResponse`。

`HEAD` 没有独立 handler 时复用 `GET` 的 status 与 headers，但不发送 body；method 不匹配返回 `405`。

## SSR、首屏交接与 SSG

页面请求使用 server route tree：

1. 创建 request-scoped `QueryClient`；
2. 匹配 route 并执行 loader；
3. 构建 `RouteDocument`；
4. 输出语义 HTML、metadata 与 Query/loader state；
5. 当前终点存在 Flutter page 时注入 Flutter bootstrap；
6. Flutter 启动后恢复首屏数据，后续导航交给 `OdroeRouter`。

Document 是纯 HTML route 的正式页面，也是混合 Flutter route 面向 SEO/GEO 的可读内容。它不把 widget tree 翻译成 DOM；纯 Document route 不加载 Flutter。

```sh
dart run odroe build -- web --release
```

Web 构建会启动真实服务端产物并请求 route，把 HTML 写入 `build/web/<route>/index.html`。静态 route 自动加入，站内链接可发现动态 route。纯 Document 应用不需要 Flutter Web build。`public/` 会复制到输出目录。

## 宿主

`OdroeServer.handle` 的合同只有：

```dart
ServerRequest -> Future<ServerResponse>
```

默认 Dart IO 宿主：

```dart
import 'package:odroe/server_io.dart';

import 'routes.server.dart';

Future<void> main() async {
  final server = createServer();
  await IoServer.bind(server.handler, port: 3000);
}
```

其他宿主只需转换 `ServerRequest` 与 `ServerResponse`。Router、Query、RPC 与用户文件结构不依赖 Dart IO。
