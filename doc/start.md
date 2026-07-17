# Odroe Start

Start 是 Odroe 的全栈运行与构建产品。它复用 Router 的同一棵 `AppRoute` tree，并把 `server.dart`、Server Function、Query handoff 和宿主 adapter 接成一个应用；它不是 Flutter Web 的别名，也不绑定数据库或某个 HTTP server。

## 正常开发入口

```sh
# 生成 client-safe routes.dart、server-only routes.server.dart
dart run odroe generate

# 启动 Start，并把 target 选择交给 flutter run
dart run odroe dev

# Flutter 参数放在 -- 后，仍由 Flutter CLI 解释
dart run odroe dev -- -d macos

# 只运行服务端
dart run odroe dev --server-only --port 3000

# 明确选择 Flutter build target，同时构建 Start server
dart run odroe build apk
dart run odroe build web --release

# 只构建当前宿主平台的 Start server executable
dart run odroe build --server-only
```

`dev` 不默认 Web，也不替用户选择 Android、iOS、桌面或其他 target。它会 watch `lib/`：route contract 或 server 实现变化时重新生成并重启 Start；普通 `page.dart` 修改由 Flutter hot reload 承接。

`generate` 产生三个普通构建产物：

- `lib/routes.dart`：Flutter/client-safe route tree、destination facade、typed server-function refs；
- `lib/routes.server.dart`：server route tree、真实 function manifest、`createStartApplication()`；
- `.dart_tool/odroe/server.dart`：默认 Dart IO host bootstrap。

这些文件不使用 annotation、`part` 或 build_runner。`server.dart` 从不被 `routes.dart` import。

## `server.dart`

每个 route 的 `server.dart` 复用同目录 `route.dart`，并导出最终 `route` fragment：

```dart
import 'package:odroe/start.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  middleware: [requireSession],
  load: (context) => context.query.ensureQueryData(postQuery(context.params.id)),
  handlers: {
    StartMethod.get: (context) => StartResponse.json({
      'id': context.params.id,
    }),
  },
);
```

它同时可以声明 App 内部 RPC：

```dart
final updatePost = ServerFunction<Map<String, Object?>, bool>(
  middleware: [requireSession],
  handler: (context) async {
    await repository.update(context.data);
    return true;
  },
);

final watchViews = ServerFunction<NoServerInput, Stream<int>>(
  handler: (_) => analytics.watchViews(),
);
```

Server Function 变量必须是公开、稳定的顶层声明。编译器用源文件路径和声明名生成内部 ID；用户不维护 ID、registry、hash 文件或胶水代码。

## Client-safe Server Function

生成的 function ref 位于对应 route facade：

```dart
final rpc = StartRpcClient(
  baseUri: Uri.parse('https://example.com'),
  transport: HttpStartTransport(),
);

final updated = await routes.posts.postId.updatePost.call(rpc, {
  'title': 'Odroe',
});

final views = await routes.posts.postId.watchViews.call(
  rpc,
  const NoServerInput(),
);
await for (final count in views) {
  // typed Stream<int>
}
```

普通返回值使用 `ServerFunctionRef<I, O>`，流使用 `ServerStreamFunctionRef<I, T>`。两者分开是为了让 Dart 在运行时保留 stream element type，而不是用不安全的 `Stream<dynamic>` cast 冒充强类型。

默认 transport 使用 `package:http`，因此可运行于 Flutter 支持的平台。测试、同进程执行和自定义宿主可实现 `StartTransport`；协议不依赖 socket。

## Serialization

默认 wire protocol 支持 JSON-like 值，以及 `DateTime`、`Duration`、`Uri`、`BigInt`、`Uint8List`。领域类型注册一个 tagged adapter：

```dart
final serializer = StartSerializer(
  adapters: [PostIdAdapter()],
);

final app = createStartApplication(serializer: serializer);
final rpc = StartRpcClient(
  baseUri: origin,
  transport: HttpStartTransport(),
  serializer: serializer,
);
```

自定义类型应位于 client/server 都可导入的共享文件，并在 `server.dart` 中使用带 prefix 的 import。编译器只把该共享类型 import 转发到 `routes.dart`，不会转发服务端实现。

Server Function 的边界仍是不可信输入。Serializer 恢复类型表示，授权和领域校验必须在 function 或 middleware 内执行。

## Middleware 与 request context

执行次序为：全局 middleware → 父 route middleware → 子 route middleware → function/HTTP handler → 反向返回。

```dart
const sessionKey = StartContextKey<Session>('session');

Future<StartResponse> requireSession(
  StartRequestContext context,
  StartNext next,
) async {
  final session = await authenticate(context.request);
  context.set(sessionKey, session);
  return next();
}
```

`StartContextKey<T>` 保持 request-scoped 值的类型。每个请求也拥有独立 `QueryClient`，不会跨用户共享服务端缓存。

Server Function 默认经过 same-origin CSRF middleware。浏览器请求必须提供可验证的 `Origin`、`Referer` 或 `Sec-Fetch-Site`；只有明确设置 `StartOptions(allowRpcWithoutOrigin: true)` 才可放宽。

## Server Route 与 Server Function 的边界

- Server Function 是同一个 Odroe App 的 typed RPC，框架处理 serialization、错误、redirect、not-found 和 stream；
- Server Route 是公开 HTTP endpoint，适合 webhook、文件、第三方 API 和自定义协议，直接返回 `StartResponse`；
- `HEAD` 在没有独立 handler 时复用 `GET` 的 status/headers，但不发送 body；
- method 不匹配在读取 payload 前返回 `405`。

两者共享 adapter-neutral `StartRequest`、`StartResponse`、middleware 和 request context，但不是同一个用户心智。

## Query 首屏交接

页面请求匹配 server route tree 后：

1. 创建 request-scoped `QueryClient`；
2. 并行执行匹配 route 的 loader；
3. 对同 key 请求去重；
4. dehydrate 成功和 pending Query；
5. renderer 输出 location、loader data 与 Query state；
6. Flutter 端用 `StartHandoffClient` hydrate 同一个 client；
7. pending Query 完成后继续发送 frame。

JSON 客户端在没有 pending Query 时收到普通 JSON；存在 pending Query 时收到 `application/x-ndjson`，首 frame 为 `initial`，后续为 `query` 或安全的 `queryError`。默认 HTML renderer 先发送可读取的 initial state，再追加 `<script type="application/json" data-odroe-frame>`，不会为了慢 Query 阻塞首字节。

`StartHandoffClient.apply(frame)` 同时支持初始 payload 与流式 frame，并使用 Query hydration 的时间仲裁避免旧服务端状态覆盖更新后的客户端数据。

## 宿主与部署

`StartApplication.handle` 的合同只有：

```dart
StartRequest -> Future<StartResponse>
```

`package:odroe/start_io.dart` 提供开箱即用的 Dart IO adapter。Relic、Cloudflare/Dart runtime、测试内存宿主或未来提取的基础设施只需转换 request/response，不应改变 Router、Query、RPC 或用户文件结构。

默认生成的 `createStartApplication()` 可传入全局 middleware、serializer、renderer 和 options。需要自定义部署生命周期时，直接导入 `routes.server.dart` 并把 `app.handler` 交给自己的 adapter。
