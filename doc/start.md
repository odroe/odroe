# Odroe Start

Start 是 Odroe 的全栈运行与构建产品。它复用 Router 的同一棵 `AppRoute` tree，并把 `server.dart`、Server Function、Query handoff 和宿主 adapter 接成一个应用；它不是 Flutter Web 的别名，也不绑定数据库或某个 HTTP server。

本地 runtime 基准可运行 `dart run benchmark/start.dart`，覆盖完整 typed RPC serialization 与 route + Query handoff，而不是只测一个脱离产品链路的 Map lookup。

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
dart run odroe build -- web --release

# 只构建当前宿主平台的 Start server executable
dart run odroe build --server-only
```

`dev` 不默认 Web，也不替用户选择 Android、iOS、桌面或其他 target。它会 watch `lib/`：route contract 或 server 实现变化时重新生成并重启 Start；普通 `page.dart` 修改由 Flutter hot reload 承接。

`generate` 产生三个普通构建产物：

- `lib/routes.dart`：Flutter/client-safe route tree、destination facade、typed server-function refs；
- `lib/routes.server.dart`：server route tree、真实 function manifest、`createStartApplication()`；
- `.dart_tool/odroe/server.dart`：默认 Dart IO host bootstrap。

这些文件不使用 annotation、`part` 或 build_runner。`server.dart` 从不被 `routes.dart` import。

Flutter 应用使用标准入口后，不需要手动组装 Router、Query 和 handoff：

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

import 'routes.dart';

void main() => runOdroeApp(
  routes: routeTree,
  builder: (app) => MaterialApp.router(routerConfig: app.router),
);
```

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

默认 wire protocol 支持 JSON-like 值、递归的 `List`/`Set`/`Iterable`/`Map<String, T>`，以及 `DateTime`、`Duration`、`Uri`、`BigInt`、`Uint8List`。文件路由编译器会为 generic collection 自动生成输入与输出 decoder，不要求用户写 cast。领域类型注册一个 tagged adapter：

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

自定义类型应位于 client/server 都可导入的共享文件，并在 `server.dart` 中使用带 prefix 的 import。编译器只把 decoder 必需的共享类型 import 转发到生成文件，不会把服务端实现转发到客户端。

Record、`Future`、嵌套 `Stream`、非 String key Map，以及没有内置 serializer 的 typed-data 类型会在生成阶段报出源文件诊断，而不是留到 RPC 运行时 cast 失败。手动组装 generic collection Server Function 时，可分别通过 `ServerFunction.decodeInput` 与 `ServerFunctionRef.decodeOutput` 提供 decoder。

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

`runOdroeApp` 在浏览器启动时读取并移除 initial state，把服务端 loader data 直接交给第一次 Flutter navigation，随后持续消费流式 frame。`StartHandoffClient.apply(frame)` 也可独立使用，并通过跨 server/client 时钟换算与更新时间仲裁，避免迟到的服务端错误或旧数据覆盖客户端新状态。

同一次请求也会执行匹配链上的 `RouteDocument` builders，合并 title、description、canonical、meta、link、JSON-LD 与语义 body。它不把 Flutter widget tree 翻译成 DOM：Document 是纯 HTML route 的正式 UI，也是混合 Flutter route 面向 SEO/GEO 的可读补充。只有当前终点实际存在 `page.dart` 时才会注入 handoff、Flutter bootstrap 与用于嵌套地址资源解析的 base URL；同一应用中的纯 Document route 仍保持纯 HTML。Flutter 第一帧后隐藏辅助 DOM，首屏 loader/Query 不会重复请求。

## SSG

```sh
dart run odroe build -- web --release
```

构建顺序固定为：生成 route targets → 编译 Start server → Flutter Web build → 启动真实 Start artifact → 并发请求静态 route → 抓取站内链接发现动态 route → 写入 `build/web/<route>/index.html`。任一路由失败会令构建失败；站外 URL、query、路径穿越和超长输出路径不会写盘。

纯 Document 应用没有 Flutter page/shell，直接运行 `dart run odroe build` 即可生成 HTML。`public/` 会复制到静态输出。需要只构建 server 或关闭 prerender 时，可显式使用 `--server-only` 或 `--no-prerender`。

## 宿主与部署

`StartApplication.handle` 的合同只有：

```dart
StartRequest -> Future<StartResponse>
```

`package:odroe/start_io.dart` 提供开箱即用的 Dart IO adapter。生成的 bootstrap 默认从 `build/web` 提供 Flutter Web 产物，也可用 `ODROE_WEB_ROOT` 改写目录；稳定文件使用 revalidation，只有带内容 hash 的文件使用 immutable cache。Relic、Cloudflare/Dart runtime、测试内存宿主或未来提取的基础设施只需转换 request/response，不应改变 Router、Query、RPC 或用户文件结构。

默认生成的 `createStartApplication()` 可传入全局 middleware、serializer、renderer、failure renderer 和 options。需要自定义部署生命周期时，直接导入 `routes.server.dart` 并把 `app.handler` 交给自己的 adapter。
