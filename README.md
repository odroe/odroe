# Odroe

Odroe 是面向 Dart 与 Flutter 产品的单包、可组合全栈元框架。当前 Flutter 产品入口面向
Android、iOS 与 Web；示例源码已在临时生成的 host scaffold 中通过 Web、
Android APK 与 iOS `--no-codesign` release build。该证据不等于签名、真机或
商店发布。只有应用选择 Web 时，Document 的 SSR/SSG 与 Flutter 首屏交接才
参与构建。

Odroe 不提供一个暗中装配全部能力的全局对象。应用显式选择 modules；Router、Query、Document、RPC 与 Server 也都能独立导入。

## 入口

| 入口 | 能力 |
| --- | --- |
| `odroe.dart` | 平台中立的 `Module`、binding、`AppContext` 与生命周期 |
| `odroe_flutter.dart` | Flutter `App` 组合根、binding 与常用 Module 构造器 |
| `query.dart` | 平台中立的 Query、Mutation、cache、hydration 与 persistence |
| `query_flutter.dart` | Query Flutter provider、builders 与 `QueryModule` |
| `router.dart` | 基于 Roux 的中立强类型 route、params/search、matching 与 URL 生成 |
| `router_flutter.dart` | `PageRoute`、`ShellRoute`、`AppRouter` 与 `RouterModule` |
| `document.dart` | 语义 HTML、metadata、SEO/GEO、SSR/SSG renderer |
| `document_flutter.dart` | Flutter Web 首屏 handoff 与 `DocumentModule` |
| `mdc.dart` | renderer-neutral MDC AST、parser、组件与安全 HTML renderer |
| `mdc_flutter.dart` | MDC Flutter renderer、controller 与样式入口 |
| `press.dart` | 平台中立的不可变内容集合与 `PressPage` |
| `press_io.dart` | 文件系统 MDC discovery、原子 snapshot 与缓存 |
| `database.dart` | typed SQL transport、`SqlQueries`、row codec 与 transaction capability |
| `database_sqlite.dart` | 已验证的 native SQLite driver 与 append-only SQL migration runner |
| `database_postgres.dart` | 已验证的 PostgreSQL driver |
| `database_mysql.dart` | Preview MySQL/MariaDB 单连接与惰性有界 pool |
| `database_d1.dart` | Preview Cloudflare D1 binding adapter |
| `rpc.dart` | 强类型 refs、client、transport、serialization 与 `RpcModule` |
| `server.dart` | 平台中立应用 core、HTTP、server functions、serializer、middleware、route 与 `Server` |
| `server_io.dart` | Dart IO host 与 prerenderer |
| `server_fetch.dart` | Preview Fetch/JavaScript host adapter |

无后缀入口保持平台中立。平台实现放在明确入口中：`*_flutter.dart`、
`*_io.dart`、`server_fetch.dart` 与各 `database_<driver>.dart`。

入口与 module 控制公开 API、运行时装配和可达的 Dart 代码，但不把单包的 pub
依赖变成可选依赖。应用仍会解析这一份共享依赖图；默认 SQLite 配置的 native
build hook 即使在入口未导入该 driver 时也会生成动态库。Odroe 的 Native build
因此使用 [`dart build cli`](https://dart.dev/tools/dart-build) 并发布完整 bundle；
应以目标平台的实际产物衡量成本。

## 创建应用

当前版本通过源码使用。`odroe create` 从空路径创建 Flutter 宿主、添加当前
Odroe checkout，并由目标工程自己的 CLI 初始化完整全栈 starter：

```sh
git clone https://github.com/odroe/odroe.git
cd odroe
flutter pub get
dart run odroe create ../my_app --odroe-path .
cd ../my_app
dart run odroe dev -- -d chrome
```

默认创建 Android、iOS 与 Web；可用 `--platforms`、`--org` 和
`--project-name` 显式控制 Flutter scaffold。缓存已准备时可加 `--offline`。
目标路径必须不存在且直接父目录必须存在；CLI 先在同父目录的私有 staging 中
完成全部工作，成功后才发布目标。失败或已处理的中断只清理该 staging。它不
覆盖已有路径，也不执行 npm、数据库迁移、构建、远程部署或平台配置变更。
依赖解析默认可能访问当前配置的 pub registry；`--offline` 才是纯缓存模式。

```text
my_app/
├── lib/
│   ├── main.dart              # one-import Flutter composition root
│   ├── posts.dart             # 客户端安全的 Post / PostPage / input records
│   ├── posts_database.dart    # shared typed schema and query
│   ├── rpc_origin.dart
│   ├── server.dart            # native / Cloudflare conditional export
│   ├── server_native.dart     # persistent SQLite
│   ├── server_cloudflare.dart # invocation-scoped D1
│   ├── routes/
│   │   ├── route.dart
│   │   ├── page.dart          # typed infinite query + create mutation
│   │   └── server.dart        # typed cursor-page/create RPC + SQL
│   ├── routes.dart            # generated client tree
│   └── routes.server.dart     # generated server tree
├── migrations/
│   ├── 0001_posts.sql
│   └── 0002_unify_posts.sql
├── package.json
├── package-lock.json
└── wrangler.jsonc
```

`init --full-stack` 只接受 Flutter `--empty` 应用，验证目标项目确实解析到正在
运行的 Odroe，然后原子写入一条真实纵向产品：Flutter 的有界游标分页与创建 → Infinite Query / Mutation →
named-record typed RPC → Server → typed SQL → SQLite。它同时准备 D1 migration 与
锁定的本地 Cloudflare 工具链，但默认开发路径不需要 Node。二次执行零改动；发现
自定义源码、配置、目录冲突或符号链接会整体拒绝，不提供 `--force`，也不会修改
pubspec 或平台宿主。

Native 默认把 SQLite 数据保存在项目的 `.odroe/app.sqlite3`，并在监听前将
`migrations/*.sql` 逐文件原子应用。初始化器会将 `.odroe/` 加入 `.gitignore`。
`ODROE_SQLITE_PATH` 与 `ODROE_MIGRATIONS_PATH` 可分别覆盖数据和 migration 路径；
生产环境应使用持久卷上的绝对数据库路径。相对路径以 server 进程的当前目录为
基准。`odroe dev` 会监听实际 migration 目录并在 SQL 变化后重启 Native server；
构建可搬运 bundle 时显式传入 `--sqlite-migrations migrations`，不会把其他数据库
项目的同名目录误判为 SQLite history。

只需要 Document 与 Router 时，改用 `dart run odroe init`；未修改的基础 starter
可以随后原子升级为 `--full-stack`。

每个包含 `page.dart`、`shell.dart` 或 `server.dart` 的目录必须包含自己的中立 `route.dart`。没有 flat-route 语法、annotation、`part`、build_runner、registry 或 hash 清单。

## 组合应用

```dart
import 'package:flutter/material.dart';
import 'package:odroe/odroe_flutter.dart';

import 'rpc_origin.dart';
import 'routes.dart';

void main() {
  runApp(
    App(
      webPathUrls: true,
      modules: <Module>[
        QueryModule(),
        RpcModule.http(baseUri: rpcBaseUri()),
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

其中 `rpc_origin.dart` 让 Web 保持同源，并要求原生应用明确选择服务端：

```dart
import 'package:flutter/foundation.dart';

Uri? rpcBaseUri({
  bool isWeb = kIsWeb,
  String nativeOrigin = const String.fromEnvironment('ODROE_API_ORIGIN'),
}) {
  if (isWeb) return null;
  if (nativeOrigin.isEmpty) {
    throw StateError('Set ODROE_API_ORIGIN with --dart-define for native RPC.');
  }

  final uri = Uri.tryParse(nativeOrigin);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw FormatException(
      'ODROE_API_ORIGIN must be an absolute HTTP(S) origin.',
      nativeOrigin,
    );
  }
  return uri;
}
```

原生运行时传入例如
`--dart-define=ODROE_API_ORIGIN=https://api.example.com`。缺失或错误的地址会在
应用启动时失败，不会拖到首次请求。仓库内的
[`example/app/lib/rpc_origin.dart`](https://github.com/odroe/odroe/blob/main/example/app/lib/rpc_origin.dart)
是同一份已测试实现。

删掉任意 module 就会删掉对应集成；`odroe.dart` 本身不创建 Query、Router、RPC、Provider 或 transport。独立使用 Router 时也可以直接创建 `AppRouter(routes: ...)`。

module 一经惰性 iterable 产出即把所有权交给 `AppContext`。枚举、注册或初始化
任一阶段失败，已产出的全部 module 都会逆序回滚；module 的 `dispose` 必须容忍
setup 尚未开始或只完成一部分。并发与重复 `dispose()` 共享同一 Future，清理完成后
context 的新读取会 fail closed。setup 期间调用公开 `dispose()` 会直接失败，避免
初始化在已销毁 context 上继续；清理只能读取已创建值，不能在 owner 释放后首次物化
lazy factory。Flutter `App` 保持同一合同，并把 rollback 的次级错误与卸载清理错误
交给 `FlutterError`。

Document SSR 会用服务端 `Server` 的 `Serializer` 编码已完成与 pending 的
Query 数据，再由 Flutter 的 `DocumentModule` 解码。默认配置可往返
`DateTime`、`Duration`、`Uri`、`BigInt` 与 `Uint8List`。自定义 wire 类型应从
同一个 adapter 配置分别创建服务端与客户端 serializer，并把客户端实例同时交给
`RpcModule.http` 与 `DocumentModule`；Odroe 不依赖隐式全局 serializer。
Flutter Web 的初始 handoff、流式 frame、语义 HTML 隐藏与 Router 站外导航在
JavaScript 和 WebAssembly 构建中使用同一套浏览器实现。上面的路由应用在组合根
`App` 显式设置 `webPathUrls: true`，于 `runApp` 前安装 Flutter 官方 Path URL
strategy，使惰性 modules 中的 Router 也能让 typed path/search 与服务端、SSG
地址保持一致。省略该参数会保留 Flutter 或宿主应用已经选择的 URL strategy；
若浏览器地址和 prerender handoff 不同，客户端会丢弃那份旧 loads/query handoff，
按当前地址重新加载。只有明确部署 hash routing 时才设置 `webPathUrls: false`。

`ContextKey`、`RouteCapability` 与 `RequestKey` 按实例身份匹配，不按名称
匹配。自定义 key 应保存为一个顶层 `final`，并在提供、读取或附加能力时复用
同一实例；名称只用于诊断。把旧的 `const ContextKey(...)`、
`const RouteCapability(...)`、`const RequestKey(...)` 声明改成 `final`；
不要在读取处重新创建 key。这样不同模块可以安全使用相同的自然名称，而不会
静默覆盖彼此。注册值使用 `key.provide(registry, value)` 或
`key.provideFactory(registry, create)`；可选 route 能力使用
`key.attach(route, value)`；请求值使用 `key.set(context, value)`。这些
key-first 实例方法会在分析期拒绝直接错型，并在 key 被泛型宽化后保留运行时
类型校验。

`QueryKey<T>` 与上述实例身份 key 不同，它是可序列化的值身份，也是 cache 中数据的
精确类型合同。构造时会递归复制并冻结 JSON-like parts；调用方之后修改嵌套 List
或 String-keyed Map，不会改变 cache identity、prefix matching、hydration 或持久化
后的 key。独立保存 key 时显式写出类型，例如
`final QueryKey<Post> postKey = QueryKey('posts.detail', [id]);`；内联放入
`QueryOptions<Post>` 时可由上下文推断。同一 `QueryClient` 的 query cache 中，同一个
canonical key 只能绑定一个精确的 `T`；`QueryKey<int>` 不能通过协变当作
`QueryKey<num>` 读写。错型注册、读取或写入会抛出 `StateError`，原 query cache
entry 保持不变。Mutation key 只是 mutation defaults/filter 的操作身份，不绑定
mutation 结果类型。

`T` 不参与 canonical、相等比较、JSON 或 prefix matching。目标 query cache 尚无
entry 时，序列化 handoff 会先恢复为 dynamic placeholder。completed data 会在 typed
读取或 adoption 前校验，错型时保留 placeholder；pending options 可以立即 adopt 为
typed entry，Future 完成时再校验，错型会让该 typed query 进入 error。用于 prefix
filter 的独立 key 应显式声明为 `QueryKey<Object?>`。优先使用小型标量 ID，只有资源
身份本身是结构化值时才放入 List 或 Map。

`QueryClient.clear()` 会取消尚在等待网络或串行 scope、还没开始下一次尝试的
mutation，并让其 Future 以 `MutationCancelledException` 结束，同时释放 cache 与
online listener。已经进入 mutation function 的副作用仍由应用负责；清空 cache
不能回滚副作用，也不会强行中断正在执行的 Future。
未订阅 listener 时，`QueryObserver.refetch()` 也会返回本次执行后的最新状态。
interval polling 若遇到慢于 interval 的 active fetch，会复用同一个 Future，不会
周期性取消并重启网络请求。

浏览器端 RPC 只支持同源，可让 `rpcBaseUri()` 返回 `null`，由
`RpcModule.http` 使用当前 origin。Android、iOS 与桌面应用必须传入明确的
HTTP(S) 服务端地址。应用可用
`headersProvider` 在每个请求发送前读取最新 token：

```dart
String? accessToken;

final rpcModule = RpcModule.http(
  baseUri: rpcBaseUri(),
  headersProvider: () {
    final token = accessToken;
    return token == null
        ? Headers()
        : Headers.single(<String, String>{
            'authorization': 'Bearer $token',
          });
  },
);
```

token 的获取、存储与更新由应用负责。provider 每个 RPC 请求只调用一次；
Odroe 会复制其结果，再写入自己拥有的协议头。`RpcClient` 不会自动重试，
因此应用可依据 `RemoteServerException.status` 决定是否刷新 token 或重试。
非 2xx HTTP 响应若没有有效 RPC error frame，会保留状态码并归类为
`RemoteServerException`；2xx 响应中的畸形或未知 frame 则是
`RpcProtocolException`。返回类型明确写成 `ServerResponse` 时会跳过这些
分类，由调用方负责读取和释放原始响应。

typed frame 必须使用 `version: 1`。`notFound` 只接受 HTTP 404，`redirect`
frame 的 status 必须与 HTTP status 相同；不一致的 2xx 响应是协议错误，
不一致的非 2xx 响应保留远端 HTTP status，不能伪装成本地控制流。

RPC 有四个独立字节边界：服务端请求、服务端 typed 输出、客户端 HTTP 请求
body，以及客户端 typed 响应；生成入口与默认 HTTP 模块均可直接配置：

```dart
import 'routes.server.dart' as generated;

final rpcModule = RpcModule.http(
  baseUri: rpcBaseUri(),
  maxRequestBodyBytes: 2 * 1024 * 1024,
  maxResponseFrameBytes: 2 * 1024 * 1024,
);

final server = generated.createServer(
  maxFunctionPayload: 2 * 1024 * 1024,
  maxFunctionResponseFrameBytes: 2 * 1024 * 1024,
);
```

`Server.maxFunctionPayload` 默认 1 MiB，限制一个 server-function 请求。
服务端超限会返回 HTTP 413；typed 客户端将其归类为保留 status 的
`RemoteServerException`。
`Server.maxFunctionResponseFrameBytes` 也默认 1 MiB，按完整 typed JSON
envelope 的 UTF-8 字节计数；stream 每个 frame 独立计数，换行不计入。
服务端直接编码 UTF-8 并在超限时停止：value 改为有界 500 error frame，stream
写入一个有界终止 error frame 并取消上游。预算最小为 28 bytes，以保证仍可发送
带 `version: 1` 的合法 error frame。显式 `ServerResponse` 保持旁路，由应用负责流式读取和限制。

畸形 JSON、未知 serializer tag 或不符合生成类型的 RPC 输入会在 handler 启动前
返回受控 HTTP 400，不触发 `Server.onError`；handler 自身抛出的同类异常仍属于
unexpected failure，并按 500 上报。

这道服务端预算约束框架生成和发送的 JSON bytes，但 `Serializer.encode` 仍会先
物化一个值的 JSON-compatible 对象图；它不能约束 handler 已有对象、超大或无限
`Iterable`。大结果仍应分页、拆成多个 stream frame 或放入对象存储。

`RpcClient.maxResponseFrameBytes` 默认 1 MiB，在 UTF-8 解码前再次防御旧版或
不可信服务端。value 的完整 JSON 算一个 frame；stream 不限制累计大小。超限会
取消响应体；2xx 归类为 `RpcProtocolException`，非 2xx 保留
`RemoteServerException.status`。

默认 `HttpTransport.maxRequestBodyBytes` 是 10 MiB。它会在调用
`Client.send` 前完整缓冲 body，exact limit 可发送，超限会取消 body 并抛出
公开的 `PayloadTooLargeException`。该预算不限制 GET query；typed RPC 也已在
进入 transport 前生成完整 JSON，因此提高它不会把 JSON 调用或上传变成流式。
这个异常发生在客户端、网络请求开始前；GET payload 只经过服务端输入预算。

RPC value 与 stream 都接收应用拥有的取消信号。Query 不依赖 RPC；把
`QueryCancelToken` 显式接到生成的 ref 即可在 `cancelQueries` 或最后一个
observer 离开时终止默认 HTTP 请求：

```dart
final post = await routes.posts.postId.readPost(
  app.read(rpcClientKey),
  postId,
  cancelled: context.cancelToken.whenCancelled.then<void>((_) {}),
);
```

信号完成后客户端抛出 `RpcCancelledException`。预先取消的调用不会启动
`headersProvider` 或 transport；provider 尚未返回时也不会发送请求。
`RpcClient` 会停止读取 typed value/stream 并取消上游订阅，默认
`HttpTransport` 还会中止请求体、响应头与响应体。自定义 `RpcTransport`
仍必须观察 `ServerRequest.cancelled`，以释放自身拥有的 I/O；调用方注入的
自定义 `Client` 可能不支持物理中止，但不会阻止 typed 调用及时结束。
`Client` 由 `package:odroe/rpc.dart` 直接导出，使用或注入标准 Client 不需要额外
导入 `package:http`；实现 `BaseClient` 或使用 request/response 等高级 API 时，
应用仍应直接依赖 `package:http`。
需要总超时时可直接传入
`Future<void>.delayed(const Duration(seconds: 10))`，Odroe 不预设 total、
setup 或 stream idle timeout。

取消只表示调用方不再等待，不能回滚已经开始的 POST、事务或其他服务端副作用；
需要协作式停止时，handler 应观察底层 `ServerRequest.cancelled`。Odroe 不因
取消自动重试。

服务端会把 unexpected module setup/rollback cleanup、middleware、handler、
loader、renderer、RPC 编码和 response stream 异常报告给 `Server.onError`。
module setup 失败会在 response 创建前报告并原样抛出；request execution 失败
仍返回安全 500；typed stream 仍发送有界终止 frame，raw stream consumer 仍
收到原始 error。默认 reporter 把 error 与 stack trace 写入当前 Dart `Zone`。
生产应用可在 `lib/server.dart` 入口直接接入自己的 telemetry：

```dart
import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() => generated.createServer(
  onError: (request, error, stackTrace) => telemetry.capture(
    method: request.method.wire,
    path: request.uri.path,
    error: error,
    stackTrace: stackTrace,
  ),
);
```

callback 可同步完成，也可返回有界的 `Future`。`Server` runtime 会立即调用 callback；
同步部分应保持很小，返回的 Future 会加入当前 invocation 生命周期而不等待 response。
原生 IO adapter 则在服务端 response close 尝试结束后调用 callback，并由 detached
request task 观察 Future。`HttpServer.close` 不等待该 task；`IoServer.close` 会停止
监听并等待已接收的 adapter task 收尾，然后才应调用 `Server.close` 释放应用资源。
需要跨进程退出保证的 telemetry 仍应进入应用自己的 durable queue。payload/frame 预算超限和正常取消始终属于
受控结果，不会上报。在 response 开始前的 request dispatch 中，`Redirect`、`NotFound` 与
`HttpError` 也属于受控结果；若这些或其他 error 从 response stream 抛出，则会上报
（typed frame overflow 除外）。`exposeErrors` 只决定是否向客户端披露内部细节，
不影响 reporter 收到原始 error 与 stack trace。reporter 自身同步或异步失败都不会
替换原始结果；Odroe 会退回默认 Zone 日志。

CLI 生成的 native bootstrap 只创建一次 `Server`，并把同一个实例的 `handler` 与
`onError` 交给 `IoServer.bind`。因此 static serving、development proxy、response
metadata、HTTP framing，以及 raw handler 的 omitted-body cleanup 都使用同一个
应用 reporter；handler 与 response source stream 仍由 `Server` 负责，不会重复
上报。手写入口也应保持同样接线：

```dart
final appServer = await createServer();
final nativeServer = await IoServer.bind(
  appServer.handler,
  onError: appServer.onError,
);

await IoServer.close(nativeServer);
await appServer.close();
```

`Server` runtime 的 callback 收到 handler 使用的同一个 `ServerRequest`。static 或
proxy 在 dispatch 前失败时，IO adapter 提供不含原始 body 的 metadata-only
diagnostic request；body 可能已消费或不可用，任何阶段都不应再次读取。受支持 method
的非法 forwarded authority 会在 static/proxy dispatch 前返回受控 400，不触发应用
reporter。response metadata 在提交前失败时会清除
旧 status reason、header、cookie 与 framing，再返回固定 500；提交后的 stream 失败
只能关闭连接。默认日志主动附加的请求字段只有 method 与 path，不含 query、header
或 body；error 与 stack trace 仍会原样记录，因此应用不应把敏感信息写入异常。

`ServerInvocation.onError` 是独立的 adapter-lifetime fallback，只观察没有 host
接管的 background/cleanup failure，以及 host `waitUntil` 的同步注册失败。host
成功接收 task 后，其后续 rejection 归 host 处理。

## 文件路由

`route.dart` 承载跨平台的强类型合同，以及可选的 Document 中立绑定。
Document 由 `document.dart` 提供，不是 `AppRoute` 核心参数，也不属于
`page.dart` 或 `server.dart`。

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
  id: 'posts.update',
  handler: (context) async => repository.update(context.data),
);
```

`server.dart` 是完整的服务端产品入口，直接导出平台中立的应用 core、server
function、受控 HTTP 结果与 serializer 类型；route server 不需要再导入
`odroe.dart` 或 `rpc.dart`。`rpc.dart`
专注于生成的 client refs、transport、serialization 与 `RpcModule`，并保留
client 和 server 共用的协议类型。

文件名只有一种心智：`definition.route.page(...)`、`definition.route.shell(...)`、`definition.route.server(...)`、`definition.route.document(...)`。
`ServerFunction.id` 是已发布 App 与服务端共享的 wire 合同；发布后应保持稳定。
编译器要求它是非空字符串字面量，并在整个 route tree 中拒绝重复值。省略
`id` 时仍使用原有的 `server.dart` 路径加变量名，便于现有代码渐进迁移，但
重命名文件或变量会改变该 fallback。

项目内的 named-record typedef 可以直接成为函数输入或输出。把 record 放在
客户端安全的共享文件，并在 `server.dart` 用前缀导入：

```dart
// lib/posts.dart
typedef Post = ({int id, String title});
typedef CreatePost = ({String title});

// lib/routes/posts/server.dart
import '../../posts.dart' as models;

final createPost = ServerFunction<models.CreatePost, models.Post>(
  id: 'posts.create',
  handler: (context) => create(context.data),
);
```

`odroe generate` 会为 client input、server input、server output、client output
生成对称 codec；`List<Post>`、nullable 与 stream item 会递归使用同一 record
shape。应用代码仍操作 Dart record，wire 才使用字段名 JSON object，不需要
annotation、`build_runner`、`toJson` 或手写 adapter。畸形输入在 handler 前返回
400；成功响应若不符合输出合同，客户端得到 `RpcProtocolException`。

首期只自动解析项目内、带前缀导入、非泛型且只有 named fields 的 record typedef。
positional、generic、recursive record 与非 `String` key 的 Map 会在生成期拒绝；
nominal class 继续由应用通过 `SerializationAdapter` 明确编码。

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

loader、middleware 与 server function 都可以通过 `context.read(queryClientKey)` 读取该请求显式安装的 Query client。生成入口也接受 `onClose`。`Server.close()` 会先拒绝新请求，再等待 response body、嵌套 background task 与 request module 清理，最后只调用一次 `onClose`；并发或重复关闭共享同一个 Future。不要从当前 middleware、handler 或 `onError` 内等待它，也不要在尚未消费或取消手写 `handle()` response body 时等待关闭。没有 `lib/server.dart` 时，CLI 直接使用生成的默认 server。

## 内容与静态页面

Press 将 MDC 目录读取为一个不可变、排序且原子发布的 snapshot。平台中立的 route 只导入 `press.dart`；文件系统 discovery 留在 server 或 prerender 入口。

```dart
import 'package:odroe/press_io.dart';

final docs = PressDirectory('content/docs', mount: '/docs');
final snapshot = await docs.snapshot();
final page = snapshot.page(const <String>['getting-started']);
```

应用可用 `lib/prerender.dart` 返回动态静态地址。CLI 会与文件路由的静态地址
合并、规范化、去重并排序，再通过真实 server 构建页面。默认只构建这份显式
清单；需要从页面发现额外同源 HTML 时使用 `--prerender-crawl`。

```dart
import 'content.dart';

Future<Iterable<Uri>> prerenderLocations() => docs.locations();
```

## 数据库

`database.dart` 提供小而明确的 typed SQL transport 与关系查询层。
方言必须显式选择；column receiver 固定赋值、谓词与列间比较类型。

```dart
final class Authors extends SqlTable<String> {
  Authors() : super('authors');

  late final id = column<int>('id', sqlInt);
  late final displayName = column<String>('display_name', sqlText);

  @override
  late final projection = SqlProjection.column(displayName);
}

typedef Post = ({int id, int? authorId, String title, int views});

final class Posts extends SqlTable<Post> {
  Posts() : super('posts');

  late final id = column<int>('id', sqlInt);
  late final authorId = column<int?>('author_id', nullable(sqlInt));
  late final title = column<String>('title', sqlText);
  late final views = column<int>('views', sqlInt);

  @override
  late final projection = SqlProjection<Post>(
    <SqlSelection<Object?>>[id, authorId, title, views],
    (row) => (
      id: id.read(row, 0),
      authorId: authorId.read(row, 1),
      title: title.read(row, 2),
      views: views.read(row, 3),
    ),
  );
}

final posts = Posts();
final authors = Authors();
const sql = SqlQueries(SqlDialect.sqlite);

final post = await sql
    .selectTable(posts, where: posts.id.equals(42))
    .oneOrNull(database);

final selected = await sql
    .selectTable(
      posts,
      where: posts.id.isIn(<int>[42, 44]),
      orderBy: <SqlOrder>[posts.id.ascending],
    )
    .all(database);

final nextPage = await sql
    .selectTable(
      posts,
      where: posts.id.lessThan(42),
      orderBy: <SqlOrder>[posts.id.descending],
      limit: 21,
    )
    .all(database);

final totalPosts = await sql.countRows(posts).one(database);

final authorName = authors.displayName.optional.as('author_name');
final postsWithAuthors = SqlProjection<({String title, String? authorName})>(
  <SqlSelection<Object?>>[posts.title, authorName],
  (row) => (
    title: posts.title.read(row, 0),
    authorName: authorName.read(row, 1),
  ),
);
final rows = await sql.select(
  from: posts,
  joins: <SqlJoin>[
    SqlJoin.left(
      authors,
      on: posts.authorId.equalsColumn(authors.id),
    ),
  ],
  projection: postsWithAuthors,
).all(database);

await sql
    .insertOnConflictDoNothing(
      posts,
      <SqlAssignment>[
        posts.id.set(42),
        posts.title.set('Hello'),
        posts.views.set(0),
      ],
      target: [posts.id],
    )
    .execute(database);

final inserted = await sql
    .insertMany(posts, <List<SqlAssignment>>[
      <SqlAssignment>[
        posts.id.set(43),
        posts.title.set('First'),
        posts.views.set(0),
      ],
      <SqlAssignment>[
        posts.id.set(44),
        posts.title.set('Second'),
        posts.views.set(0),
      ],
    ])
    .returning(posts.projection)
    .all(database);
final insertedById = <int, Post>{
  for (final post in inserted) post.id: post,
};

await sql.updateAll(
  posts,
  <SqlUpdateAssignment>[posts.title.set('Archived')],
  confirm: allRows,
).execute(database);

await sql.updateWhere(
  posts,
  <SqlUpdateAssignment>[posts.views.incrementBy(1)],
  where: posts.id.equals(42),
).execute(database);
```

`posts.title.set(42)` 会在分析期失败。`updateAll`/`deleteAll` 同时要求方法名
与 `allRows` 两次确认。联表查询会自动限定列名；`LEFT JOIN` 右侧的非空
schema column 通过结果专用的 `.optional` 解码，不能用于写入。
mutation 仍严格保持单表。`BoundSql` 保留为手写 SQL 逃生口。

`incrementBy` 只存在于非空 `SqlTableColumn<T extends num>`，编译为单条
`column = column + ?` UPDATE，不会先读再写。正值增加，负值减少；`0`、
`0.0` 与 `-0.0` 会在 SQL 构造前拒绝，其余值仍立即通过 column codec
绑定。UPDATE 接收公开的 `SqlUpdateAssignment`；`set` 生成的
`SqlAssignment` 也是其子类，但 `incrementBy` 的结果不能误用于 INSERT。同一
column 的 `set` / `incrementBy` 重复赋值会在 I/O 前失败。整数溢出与浮点舍入
仍遵循实际数据库 provider；Odroe 不用一层隐式数值模型掩盖它们。

`countRows` 通过相同的 table、join 与 predicate 路径生成 typed `COUNT(*)`，并直接
返回 `SqlRead<int>`。它计算 `FROM` / `JOIN` / `WHERE` 产生的关系行，因此 join
重复行会分别计数，空关系返回 `0`；API 不接受排序和分页，也不伪装成通用
aggregate DSL。Odroe 不会替分页隐式执行它；大表热路径应按数据库查询计划与索引
决定是否计数。

`isIn` / `isNotIn` 在构造 predicate 时立即消费 iterable，并通过 column codec
绑定每个非空值；Dart `null` 会先归一化，不进入 codec。后续增删或重排输入集合不会
改变查询；元素值是否复制由 column codec 决定。
它们保留非空候选的顺序与重复项，不自动去重、
分块或绕过 provider 参数上限。空 `isIn` 永不匹配；空 `isNotIn` 会直接拒绝，避免
动态排除集合让 UPDATE/DELETE 静默变成全表操作。真正的全表 mutation 应继续使用
`updateAll` / `deleteAll` 与 `allRows`。候选中的 `null` 会展开为明确的
`IS NULL` / `IS NOT NULL` 分支；候选不含 `null` 时，nullable database value
保留 SQL 三值语义，不匹配 `IN` 或 `NOT IN`。

`insertOnConflictDoNothing` 要求非空 values 与显式 conflict target；列清单必须
匹配所选数据库接受的 conflict arbiter，其他索引形态继续使用 `BoundSql`。
SQLite、D1 与 PostgreSQL 编译为同一条 target-aware
`ON CONFLICT DO NOTHING`。MySQL 没有等价的 target 语义，因此该方法会在读取
输入或访问数据库前返回 `SqlErrorCode.unsupported`，不会暗中退化为
`INSERT IGNORE` 或任意唯一键冲突处理。

`insertMany` 生成一条 multi-row `INSERT`，不是把多条 statement 包进
`atomicWrite`。外层 rows 与每一行都不能为空；每行必须使用同一张表、没有重复列，
并与首行保持完全相同的列对象和顺序。Odroe 会先验证全部输入，再构造 SQL。
它不会自动分块，调用方必须按 provider 的 bound-parameter limit 切分。SQLite、D1
与 PostgreSQL 可以继续调用 `returning`；MySQL/MariaDB 支持多行写入但不支持
`RETURNING`。数据库不保证返回行与输入行同序，必须像上例一样按稳定业务 key
关联，不能按输入下标配对。

`SqlQueries` 会把所选方言保留到每个 `BoundSql`。SQLite 与 D1 接受
`SqlDialect.sqlite`，PostgreSQL 接受 `SqlDialect.postgres`，MySQL/MariaDB
接受 `SqlDialect.mysql`；显式错配会在该 statement 到达数据库前抛出
`SqlException(SqlErrorCode.unsupported)`。

`odroe init --full-stack` 把根页面跑成一条真实纵向链路：Flutter cursor-page/create UI →
Infinite Query / Mutation → 生成的 named-record typed RPC → HTTP → Server →
`DatabaseModule` → typed SQL。它与仓库中的
[`example/app`](https://github.com/odroe/odroe/tree/main/example/app) 沿用同一组已验证
API、runtime contract 与锁定工具链。共享的产品 records 不依赖数据库：

```dart
typedef Post = ({int id, String title});
typedef CreatePost = ({String title});
typedef PostPage = ({List<Post> items, int? nextCursor});
typedef ListPostsInput = ({int? cursor, int limit});
```

server 将 `limit` 限定在 `1..50`，按唯一 ID 倒序并读取 `limit + 1` 行。
额外一行只用来决定 `nextCursor`；RPC 返回最多 `limit` 个 `items`。Flutter
用 `InfiniteQueryOptions<PostPage, int?>` 将每页的 `nextCursor` 传给下一次
`posts.list`，不会把整张表一次物化到 RPC 与 widget tree。仓库示例在
同一契约上另加 `ids` 与 `sort`：`newest` 使用 `id < cursor`，`oldest`
使用 `id > cursor`，两者都保持严格、可索引的 keyset 边界。

创建操作直接返回数据库生成的完整记录：

```dart
return postQueries
    .insert(posts, <SqlAssignment>[posts.title.set(title)])
    .returning(posts.projection)
    .one(context.request.read(databaseKey));
```

这里没有猜测下一个 ID，也没有 insert 后再做一次游离查询。`one` 要求
`RETURNING` 恰好一行；详情读取则使用 `oneOrNull`，零行返回 `null`、多行直接
拒绝，避免调用端重复维护 `limit`、列表判空与 `single` 解包。

`lib/server.dart` 通过条件导出隔离平台 driver。Native 入口使用进程拥有的文件
SQLite，默认路径为 `.odroe/app.sqlite3`，request 只借用，并由
`Server.close()` 关闭。监听前显式读取并应用应用拥有的 SQL 历史：

```dart
final migrations = readSqliteMigrations(
  Platform.environment['ODROE_MIGRATIONS_PATH'] ?? 'migrations',
);
final database = SqliteDatabase.open(databaseFile.path);
await database.applyMigrations(migrations);
```

文件名必须是 `NNNN_snake_case.sql`，版本唯一且只能向后追加。Native ledger 保存
文件名与完整 SQL；已应用文件被修改、删除、改名或在较小版本补插时，启动会在
执行 pending SQL 前失败。runner 取得 `BEGIN IMMEDIATE` 写锁后会再次校验完整
source 与 ledger，避免两个进程接受互不完整的历史。每个文件由 SQLite parser
逐 statement 执行，而不是按分号切割；文件与 ledger 行仍在同一事务提交，失败只
回滚当前文件，此前成功版本保留。`main._odroe_migrations` 是保留名，其 canonical
schema 也会在提交前验证。这里没有 schema diff、down migration 或通用 migration
DSL。

Cloudflare 入口在 `invocationModules` 中包装 D1 binding。Wrangler 消费同一组
`migrations/*.sql`，但维护自己的 `d1_migrations` ledger；Worker Fetch 不会自动
迁移。`0002_unify_posts.sql` 同时把历史 seed 演进为 provider-neutral
`Odroe post 42` 并创建索引，因此 Native 与本地 D1 会得到同一产品状态。Native
构建发布完整 bundle root：`bin/server`（Windows 为 `bin/server.exe`）是入口，
`lib/` 保存运行所需的 native libraries；选择 SQLite history 时再把 migration 原字节放入同一根目录的
`migrations/`。Worker、Flutter Web 与 Wasm 产物都不会触达 SQLite FFI。

生成的应用在自己的 `package.json` 与 lockfile 中固定 Wrangler 4.118.0；Node 22+
与 npm 10.9+ 只用于本地 Cloudflare 工具链，不进入 Dart 依赖图或部署产物。
无需全局安装 Wrangler：

```sh
npm ci
dart run odroe build --no-server --sqlite-migrations migrations web
npm run cloudflare:migrate:local
npm run cloudflare:dev
```

最后一条命令通过 `odroe dev --server-target cloudflare --server-only`
重新生成 route，并在成功编译后原子替换 server JavaScript，再调用项目锁定的
Wrangler 启动本地 Workerd；它不会直接复用可能陈旧的
`build/odroe/cloudflare`。Dart server 源码变化会重新编译并触发 Workerd reload；
成功启动后的生成或编译失败会继续服务上一份可用 Worker，修复源码后自动恢复。
首次 route 生成或编译失败则直接退出，不会运行旧 artifact。访问 `/` 会得到语义 HTML，
`posts.list` 从 D1 读取记录，`posts.create` 通过 D1 `INSERT ... RETURNING`
创建并返回完整 `Post`，随后同一列表会刷新。移除 `--local` 或运行 deploy 会
修改远端状态，不属于这条本地路径。

```dart
final statement = BoundSql.parts(
  <String>['SELECT "title" FROM "posts" WHERE "id" = ', ''],
  <SqlValue>[sqlInt.encode(42)],
  kind: SqlStatementKind.rowReturning,
  dialect: SqlDialect.sqlite,
);
final manualTitles = await database.query(
  statement,
  (row) => row.read(0, sqlText),
);
```

手写 `BoundSql.raw` / `BoundSql.parts` 默认 `dialect: null`，表示没有声明
兼容方言，driver 会继续接受；这不代表 SQL 已证明可跨数据库运行。数据库专用
SQL 应显式设置 `dialect`，以获得同样的前置保护。

PostgreSQL 可继续使用 `PostgresDatabase.open(...)` 打开一个串行连接，也可按
服务并发量选择惰性连接池：

```dart
import 'package:odroe/database_postgres.dart';

final database = PostgresDatabase.pool(
  host: 'localhost',
  database: 'app',
  username: 'app',
  password: secret,
  settings: const PoolSettings(maxConnectionCount: 4),
);
```

MySQL/MariaDB 同样保留低成本的串行 `open(...)`，服务端并发可使用 Odroe
自有的惰性有界 pool；它不增加依赖，也不会自动重试可能产生副作用的操作：

```dart
import 'package:odroe/database_mysql.dart';

final database = MysqlDatabase.pool(
  host: 'localhost',
  database: 'app',
  username: 'app',
  password: secret,
  maxConnections: 4,
  maxPendingOperations: 32,
  queueTimeout: Duration(seconds: 10),
);
```

数据库所有权必须显式。Flutter 应用级 context 应使用应用解析出的绝对可写路径，
例如 `DatabaseModule.owned(SqliteDatabase.open(appWritableDatabasePath))`；不要把
移动端持久化绑定到相对工作目录。原生服务端的 `modules` 是 request-scoped，
必须借用上面的进程级 PostgreSQL pool，并由 `Server` 的 `onClose` 在所有请求
drain 后关闭：

```dart
Server createServer() => generated.createServer(
  modules: () => <DatabaseModule>[DatabaseModule.borrowed(database)],
  onClose: database.close,
);
```

handler、loader 与 server function 通过 `context.read(databaseKey)` 取得同一
数据库。不要把 `DatabaseModule.owned(sharedDatabase)` 放入 `Server.modules`，
否则首个请求结束就会关闭共享 pool。
同一规则适用于 native SQLite 与 MySQL/MariaDB：进程创建、request 借用、
`onClose` 关闭。生成的 native bootstrap 会等待异步 `createServer()`，因此可先
`await MysqlDatabase.open(...)` 再开始监听，或同步创建惰性 pool。Cloudflare D1 则在
`invocationModules` 中为每次请求创建 `DatabaseModule.owned` wrapper；runtime
仍拥有底层 binding，Fetch 入口没有虚构的进程级 `onClose`。

PostgreSQL `pool(...)` 的默认 settings 是
`PoolSettings(maxConnectionCount: 4)`；这是控制数据库连接成本的旋钮，
应按部署环境明确调整。若传入自定义 `PoolSettings`，也应显式设置该字段；
字段为空时底层默认上限是 1。`poolUrl(...)` 同理使用
`max_connection_count` URL 参数，未设置时上限为 1。创建 pool 不会立即连接，
首次操作才会获取连接。普通顶层请求最多按连接上限并发，每次 `transaction`
或 `atomicWrite` 则固定使用同一个连接。

pool-backed 顶层调用不保证复用同一 session。临时表、`SET` 等 session-local
工作不属于 Odroe pool 合同；需要跨语句持有这类状态时，使用单连接
`open(...)`，或直接在调用方持有的 `Pool.run(...)` callback 内完成整个
工作单元。`fromPool(...)` 默认借用调用方的 pool；只有显式
`ownsPool: true` 时，`close()` 才关闭它。`pool(...)` 与 `poolUrl(...)` 创建的
pool 由数据库拥有，`close()` 会释放它。`Connection`、`ConnectionSettings`、
`Pool` 与 `PoolSettings` 均由 `package:odroe/database_postgres.dart` 导出；只有
使用 PostgreSQL 包未出现在 Odroe 公开签名中的高级 API 时，应用才需要直接依赖它。

`MysqlDatabase.pool(...)` 默认最多创建 4 条连接，并最多接受 32 个等待容量的操作。
`maxConnections` 是并发与数据库成本上限，`maxPendingOperations` 是进程内存和关停
积压上限；队列已满时新操作立即以 `SqlErrorCode.unavailable` 失败。`queueTimeout`
默认 10 秒，只计算尚未取得连接容量的等待；开始建连后改由 `connectTimeout` 限制
握手和 session 初始化。构造时不连接，首次操作才按需打开。每条连接初始化为 UTC，
`transaction` 与 `atomicWrite` 全程独占同一条连接。`close()` 先等待已经接收的活动
和排队操作，再释放所有连接；关闭后不会重新打开。连接创建失败会释放容量并推进
队列。MySQL pool 不自动 retry，也不暴露 `fromPool`、URL、状态统计或 idle tuning。
不同顶层调用不保证落在同一 session；不要手写 transaction control，也不要依赖
跨调用的临时表或 session-level `SET`，多语句工作单元必须使用 `transaction(...)`。

driver 只在 fragments 之间插入 native placeholder，不解析或重写 SQL。SQLite 与
PostgreSQL 已通过真实合同测试。D1 是 Preview，提供可选的本地
Wrangler/Workerd 合同测试；它提供原子 batch，不提供交互式 transaction。
MySQL/MariaDB 是 Preview：单连接已通过真实 MySQL 8.4 与 MariaDB 11.8，惰性
有界 pool 已通过 MariaDB 11.8。它不支持 nested transaction、multiple result sets、
portable `TIME` 解码或 `SqlDialect.mysql` 的 `RETURNING`。pool 在 transaction control 状态
不确定时直接淘汰物理连接，避免把未清理的 session 交给下一次请求。

D1 会把 Cloudflare 明确的网络丢失、storage reset、代码更新 reset 与远端节点瞬时
解析故障映射为 `SqlErrorCode.unavailable`；其他容量、过载、CPU、内存或超大写入
超时仍保持 `driver`。Odroe adapter 不增加重试；Cloudflare runtime 仍可能按其合同
自动重试只读查询。应用只能在自己能证明操作幂等时增加重试。

MySQL 的无绑定值语句会在 I/O 前拒绝 `;`，以阻止 text protocol 执行多条
语句；不要给手写 MySQL SQL 添加尾分号。带绑定值的语句使用 prepared
protocol。

顶层调用可把手写 SQL 保持为默认的 `unknown`，但错误 terminal 可能要在
数据库执行后才能识别；已知形态时应显式标记。`atomicWrite` 与 transaction
callback 必须声明 `write` 或 `rowReturning`，因此 transaction control
与会隐式提交的 DDL 不会被误放进框架管理的事务。
由于 D1 raw result 无法区分空查询与写入，D1 的 `query` 还会在发送前要求
`rowReturning`；`SqlQueries` 已自动提供该标记。

`NotFound` 与 `Redirect` 也由 `package:odroe/rpc.dart` 作为 client/server
共用的受控结果导出，client 可以直接捕获；server-function 实现统一从
`package:odroe/server.dart` 使用，无需第二个产品入口。

## CLI

```sh
dart run odroe create ../my_app --odroe-path .
dart run odroe init
dart run odroe generate
dart run odroe dev --server-only
dart run odroe dev --server-target cloudflare --server-only
flutter devices
dart run odroe dev -- -d <ios-device-id> --dart-define=ODROE_API_ORIGIN=https://api.example.com
dart run odroe dev -- -d chrome
dart run odroe build --no-server -- apk --dart-define=ODROE_API_ORIGIN=https://api.example.com
dart run odroe build --no-server --sqlite-migrations migrations web
dart run odroe build --no-server -- web --wasm
dart run odroe build --sqlite-migrations migrations web
dart run odroe build --server-only --server-target cloudflare
dart run odroe build --server-target cloudflare web
```

Native target 的 `--server-artifact` 指向完整 bundle root，而不是可执行文件。
默认目录是 `build/odroe/server`；类 Unix 入口为 `bin/server`，Windows 为
`bin/server.exe`。运行所需的 native libraries 保留在 `lib/`；选择 SQLite
history 时还包含 `migrations/`。从 bundle 根运行入口，部署时不要单独复制该文件。
Cloudflare target 的该选项仍指向编译后的 `server.js`。

将 `<ios-device-id>` 替换为 `flutter devices` 返回的设备标识。`dev` 不默认
Web；`--` 后参数原样交给 Flutter CLI。包含 RPC 的原生运行与构建必须传入
`ODROE_API_ORIGIN`，Web 继续使用同源。开发 server 直接挂载源码 `public/`，
不读取旧 `build/web`。带 migration 选项的 `build --no-server web` 只构建
Flutter Web 与静态产物；
带 `--sqlite-migrations migrations` 的 `build web` 还会生成包含 SQLite
history 的 native server bundle。两者都会通过真实 server
prerender 静态 route。纯 Document route 输出纯 HTML；
带 Flutter page 的 route 输出可读语义 HTML、handoff state 与原样
`/flutter_bootstrap.js`，随后由已加载的 Flutter app 承接导航。
`--no-server` 不生成可部署 server artifact，但仍运行生成的 Dart
server 源码完成 prerender，适合只部署 `build/web` 的 assets-only SSG。
CLI 会覆盖 native prerender 子进程的 `ODROE_SQLITE_PATH`，让它使用独立临时
数据库，并在子进程结束后删除。`--sqlite-migrations` 同时固定本轮读取的 source，
因此构建不读取或改写 `.odroe/app.sqlite3`，也不受继承环境中的 history 路径影响。

prerender 默认使用 4 个并发请求，最多处理 1000 个 route，每个 HTML 响应
最多 1 MiB。`--prerender-concurrency`、`--prerender-max-routes` 与
`--prerender-max-response-bytes` 可显式调整预算。需要 Cloudflare server
artifact 的构建也复用生成的 Dart server 源码完成 prerender，不再额外编译
临时 Native bundle。
纯文档构建会先写入同级 staging 目录，全部成功后才替换既有静态产物。
prerender 期间 server 明确禁用静态根，旧产物与 `public/` 中的同名 HTML
不会替代本轮真实 route 响应。

`build --server-only --sqlite-migrations migrations` 生成的 native bundle 与构建
OS/architecture 绑定。CLI 通过隐藏 ownership marker 管理整个 bundle root，不会
覆盖未标记路径；后续若漏传 migration 选项也会在发布新 bundle 前失败，避免留下
旧 history。发布会在进程锁内以完整目录替换 `bin/`、`lib/` 与可选
`migrations/`，失败时恢复上一份 bundle。
旧版单文件产物不会被隐式升级；确认并保留旧 migration history 后，需显式移走或
删除该构建产物再首次生成 bundle。
请在目标平台或兼容 builder 中构建。生成的 bootstrap 默认从进程当前目录下的
`build/web` 提供静态文件；`ODROE_WEB_ROOT` 可指定明确目录，空字符串会禁用
静态根。从 bundle root 运行时，默认位置就是 `<bundle>/build/web`。部署时必须
同时携带对应静态目录、设置显式路径，或禁用静态服务。
Native `IoServer` 会为 `publicDirectory` 中的文件逐次验证真实路径，使用
`no-cache` 配合 ETag/Last-Modified 避免重复传输，并对至少 1 KiB 的
文本、JavaScript、JSON、SVG 与 Wasm 流式发送 gzip。文件名不会被猜测为
content hash；若上游代理负责内容编码，可设置
`compressStaticAssets: false`。
精确文件始终优先；若不存在，地址会读取同路径的 `index.html`，因此
`/docs`、`/docs/` 与 `/docs.v1` 都可直接复用对应的 prerender 产物，
无需再次动态渲染。该 fallback 只接管 HTML-compatible 请求；显式
`Accept: application/json` 仍交给动态 Document handoff，并以 `Vary: Accept`
隔离缓存。
生成的 bootstrap 在所有平台监听 SIGINT，并在受支持平台监听 SIGTERM；它会先
通过 `IoServer.close` 停止接入并 drain adapter task，再调用 `Server.close`。
首个终止信号优雅等待在途请求；drain 期间的第二个信号会升级为强制关闭。
绑定失败也会释放已创建的应用资源。手写入口必须保持同一顺序。

Cloudflare target 生成 `build/odroe/cloudflare/server.js` 与薄
`worker.mjs`。平台配置仍由应用持有；Odroe 不覆盖已有
`wrangler.jsonc`。Cloudflare 开发模式要求 `--server-only`、项目本地
`node_modules/wrangler` 与 `wrangler.jsonc`；CLI 把本轮生成的
`worker.mjs` 作为 Wrangler 的显式 entrypoint，从而不会因配置仍指向旧 artifact
而静默运行陈旧代码。该模式只热更 Dart server，Flutter Web/static assets 仍由
显式 build 负责。生成的 Fetch bootstrap 只创建一次 `Server`，并把同一实例的
`invocationHandler` 与 `onError` 交给 adapter。status、header、`Response` 构造及
response byte bridge 的 adapter-owned 异常只上报一次；handler 与 source stream
仍由 `Server` 上报。异步 reporter 由 host `waitUntil` 持有，不阻塞 response。
Fetch host 没有可靠的进程 shutdown event，因此生成入口不会自动调用
`Server.close` 或 `onClose`；D1 等 binding-backed 资源保持 invocation-scoped。
若需让真实客户端断开完成 `ServerRequest.cancelled`，运行该 Fetch adapter 的
Cloudflare Worker 必须在 `compatibility_flags` 中启用 `enable_request_signal`；Node
`AbortController` smoke 不能替代该平台配置。纯静态 assets-only SSG 不运行 adapter，
无需该 flag。

官网的 assets-only 发布工具隔离在 `sites/odroe.dev/package.json`，并由 lockfile
固定为 Wrangler 4.118.0；它不会进入 Odroe 的 Dart 依赖图或线上产物。本地无上传
门禁要求 Node 22 或更新版本与 npm，Dart-only 开发不需要 Node：

```sh
cd sites/odroe.dev
npm ci
npm run build
npm run deploy:check
```

`npm run preview` 可通过本地 Workerd 验证真实 Cloudflare 静态路由。
`npm run deploy` 会创建缺失的 `odroe-dev` Worker，或立即改变现有版本与流量，
必须获得明确授权。发布前必须通过 `npm run deploy:account` 锁定并回读授权账号；
发布后运行 `npm run deploy:status`、`npm run deploy:versions` 回读版本与流量，
再对部署返回的精确 URL 做 HTTP smoke。当前本地 dry-run 与 Workerd 已验证，
尚未执行远端 Cloudflare 发布。

可运行应用见 [`example/app`](https://github.com/odroe/odroe/tree/main/example/app)。官网源码与正式文档位于
[`sites/odroe.dev`](https://github.com/odroe/odroe/tree/main/sites/odroe.dev)，由 Odroe 的 Document、Press 与 SSG
构建。当前 `odroe.dev` 外部访问受 Cloudflare 526 SSL 错误阻塞，不宣称已
线上可用。
