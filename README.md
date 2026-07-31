# Odroe

Odroe 是单包、可组合的 Flutter 全栈元框架。当前 Flutter 产品入口面向
Android、iOS 与 Web；示例源码已在临时生成的 host scaffold 中通过 Web、
Android APK 与 iOS `--no-codesign` release build。该证据不等于签名、真机或
商店发布。只有应用选择 Web 时，Document 的 SSR/SSG 与 Flutter 首屏交接才
参与构建。

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
| `mdc.dart` | renderer-neutral MDC AST、parser、组件与安全 HTML renderer |
| `mdc_flutter.dart` | MDC Flutter renderer、controller 与样式入口 |
| `press.dart` | 平台中立的不可变内容集合与 `PressPage` |
| `press_io.dart` | 文件系统 MDC discovery、原子 snapshot 与缓存 |
| `database.dart` | typed SQL transport、`SqlQueries`、row codec 与 transaction capability |
| `database_sqlite.dart` | 已验证的 native SQLite driver |
| `database_postgres.dart` | 已验证的 PostgreSQL driver |
| `database_mysql.dart` | Preview MySQL/MariaDB driver |
| `database_d1.dart` | Preview Cloudflare D1 binding adapter |
| `rpc.dart` | 强类型 server functions、client、transport 与 `RpcModule` |
| `server.dart` | adapter-neutral HTTP、middleware、route 与 `Server` |
| `server_io.dart` | Dart IO host 与 prerenderer |
| `server_fetch.dart` | Preview Fetch/JavaScript host adapter |

无后缀入口保持平台中立。平台实现放在明确入口中：`*_flutter.dart`、
`*_io.dart`、`server_fetch.dart` 与各 `database_<driver>.dart`。

## 创建应用

```sh
flutter create my_app
cd my_app
```

当前重构版先通过源码使用：

```yaml
dependencies:
  odroe:
    path: ../odroe
```

```sh
flutter pub get
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

浏览器端 RPC 只支持同源，可让 `RpcModule.http()` 使用当前 origin。
Android、iOS 与桌面应用应传入明确的服务端地址。应用可用
`headersProvider` 在每个请求发送前读取最新 token：

```dart
String? accessToken;

final rpcModule = RpcModule.http(
  baseUri: Uri.parse('https://api.example.com'),
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

RPC 有四个独立字节边界：服务端请求、服务端 typed 输出、客户端 HTTP 请求
body，以及客户端 typed 响应；生成入口与默认 HTTP 模块均可直接配置：

```dart
import 'routes.server.dart' as generated;

final rpcModule = RpcModule.http(
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
写入一个有界终止 error frame 并取消上游。预算最小为 16 bytes，以保证仍可发送
合法 error frame。显式 `ServerResponse` 保持旁路，由应用负责流式读取和限制。

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
`http.Client.send` 前完整缓冲 body，exact limit 可发送，超限会取消 body 并抛出
公开的 `PayloadTooLargeException`。该预算不限制 GET query；typed RPC 也已在
进入 transport 前生成完整 JSON，因此提高它不会把 JSON 调用或上传变成流式。
这个异常发生在客户端、网络请求开始前；GET payload 只经过服务端输入预算。

RPC value 与 stream 都接收应用拥有的取消信号。Query 不依赖 RPC；把
`QueryCancelToken` 显式接到生成的 ref 即可在 `cancelQueries` 或最后一个
observer 离开时终止默认 HTTP 请求：

```dart
final title = await routes.posts.postId.readTitle(
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
自定义 `http.Client` 可能不支持物理中止，但不会阻止 typed 调用及时结束。
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
request task 观察 Future。`HttpServer.close` 不等待该 task；需要跨进程退出保证的
telemetry 应进入应用自己的 durable queue。payload/frame 预算超限和正常取消始终属于
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
final appServer = createServer();
final nativeServer = await IoServer.bind(
  appServer.handler,
  onError: appServer.onError,
);
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
  id: 'posts.update',
  handler: (context) async => repository.update(context.data),
);
```

文件名只有一种心智：`definition.route.page(...)`、`definition.route.shell(...)`、`definition.route.server(...)`、`definition.route.document(...)`。
`ServerFunction.id` 是已发布 App 与服务端共享的 wire 合同；发布后应保持稳定。
编译器要求它是非空字符串字面量，并在整个 route tree 中拒绝重复值。省略
`id` 时仍使用原有的 `server.dart` 路径加变量名，便于现有代码渐进迁移，但
重命名文件或变量会改变该 fallback。

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

final class Posts extends SqlTable<String> {
  Posts() : super('posts');

  late final id = column<int>('id', sqlInt);
  late final authorId = column<int?>('author_id', nullable(sqlInt));
  late final title = column<String>('title', sqlText);

  @override
  late final projection = SqlProjection.column(title);
}

final posts = Posts();
final authors = Authors();
const sql = SqlQueries(SqlDialect.sqlite);

final titles = await sql
    .selectTable(posts, where: posts.id.equals(42))
    .all(database);

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

await sql.insert(
  posts,
  <SqlAssignment>[posts.title.set('Hello')],
).execute(database);

await sql.updateAll(
  posts,
  <SqlAssignment>[posts.title.set('Archived')],
  confirm: allRows,
).execute(database);
```

`posts.title.set(42)` 会在分析期失败。`updateAll`/`deleteAll` 同时要求方法名
与 `allRows` 两次确认。联表查询会自动限定列名；`LEFT JOIN` 右侧的非空
schema column 通过结果专用的 `.optional` 解码，不能用于写入。
mutation 仍严格保持单表。`BoundSql` 保留为手写 SQL 逃生口：

`SqlQueries` 会把所选方言保留到每个 `BoundSql`。SQLite 与 D1 接受
`SqlDialect.sqlite`，PostgreSQL 接受 `SqlDialect.postgres`，MySQL/MariaDB
接受 `SqlDialect.mysql`；显式错配会在该 statement 到达数据库前抛出
`SqlException(SqlErrorCode.unsupported)`。

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
final database = PostgresDatabase.pool(
  host: 'localhost',
  database: 'app',
  username: 'app',
  password: secret,
);
```

`pool(...)` 的默认 settings 是
`pg.PoolSettings(maxConnectionCount: 4)`；这是控制数据库连接成本的旋钮，
应按部署环境明确调整。若传入自定义 `PoolSettings`，也应显式设置该字段；
字段为空时底层默认上限是 1。`poolUrl(...)` 同理使用
`max_connection_count` URL 参数，未设置时上限为 1。创建 pool 不会立即连接，
首次操作才会获取连接。普通顶层请求最多按连接上限并发，每次 `transaction`
或 `atomicWrite` 则固定使用同一个连接。

pool-backed 顶层调用不保证复用同一 session。临时表、`SET` 等 session-local
工作不属于 Odroe pool 合同；需要跨语句持有这类状态时，使用单连接
`open(...)`，或直接在调用方持有的 `pg.Pool.run(...)` callback 内完成整个
工作单元。`fromPool(...)` 默认借用调用方的 pool；只有显式
`ownsPool: true` 时，`close()` 才关闭它。`pool(...)` 与 `poolUrl(...)` 创建的
pool 由数据库拥有，`close()` 会释放它。

driver 只在 fragments 之间插入 native placeholder，不解析或重写 SQL。SQLite 与
PostgreSQL 已通过真实合同测试。D1 是 Preview，已通过本地
Wrangler/Workerd；它提供原子 batch，不提供交互式 transaction。
MySQL/MariaDB 是 Preview，已通过真实 MySQL 8.4 与 MariaDB 11.8；当前为
单连接串行 driver，不支持 nested transaction、multiple result sets、portable
`TIME` 解码或 `SqlDialect.mysql` 的 `RETURNING`。

MySQL 的无绑定值语句会在 I/O 前拒绝 `;`，以阻止 text protocol 执行多条
语句；不要给手写 MySQL SQL 添加尾分号。带绑定值的语句使用 prepared
protocol。

顶层调用可把手写 SQL 保持为默认的 `unknown`，但错误 terminal 可能要在
数据库执行后才能识别；已知形态时应显式标记。`atomicWrite` 与 transaction
callback 必须声明 `write` 或 `rowReturning`，因此 transaction control
与会隐式提交的 DDL 不会被误放进框架管理的事务。
由于 D1 raw result 无法区分空查询与写入，D1 的 `query` 还会在发送前要求
`rowReturning`；`SqlQueries` 已自动提供该标记。

## CLI

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
flutter devices
dart run odroe dev -- -d <ios-device-id>
dart run odroe dev -- -d chrome
dart run odroe build apk
dart run odroe build web
dart run odroe build --server-only --server-target cloudflare
```

将 `<ios-device-id>` 替换为 `flutter devices` 返回的设备标识。`dev` 不默认
Web；`--` 后参数原样交给 Flutter CLI。开发 server 直接挂载源码 `public/`，
不读取旧 `build/web`。`build web` 会构建 Flutter Web 与 server artifact，
再通过真实 server prerender 静态 route。纯 Document route 输出纯 HTML；
带 Flutter page 的 route 输出可读语义 HTML、handoff state 与原样
`/flutter_bootstrap.js`，随后由已加载的 Flutter app 承接导航。

prerender 默认使用 4 个并发请求，最多处理 1000 个 route，每个 HTML 响应
最多 1 MiB。`--prerender-concurrency`、`--prerender-max-routes` 与
`--prerender-max-response-bytes` 可显式调整预算。Cloudflare 构建复用生成的
Dart server 源码完成 prerender，不再额外编译临时 native executable。
纯文档构建会先写入同级 staging 目录，全部成功后才替换既有静态产物。
prerender 期间 server 明确禁用静态根，旧产物与 `public/` 中的同名 HTML
不会替代本轮真实 route 响应。

`build --server-only` 生成的 native executable 与构建 OS/architecture 绑定。
请在目标平台或兼容 builder 中构建。生成的 bootstrap 默认从进程当前目录下的
`build/web` 提供静态文件；`ODROE_WEB_ROOT` 可指定明确目录，空字符串会禁用
静态根。部署时必须同时携带对应静态目录，或显式禁用。
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

Cloudflare target 生成 `build/odroe/cloudflare/server.js` 与薄
`worker.mjs`。平台配置仍由应用持有；Odroe 不覆盖已有
`wrangler.jsonc`。当前只验证了本地 Wrangler/Workerd，尚未验证远端
Cloudflare 部署。

可运行应用见 [`example/app`](https://github.com/odroe/odroe/tree/main/example/app)。官网源码与正式文档位于
[`sites/odroe.dev`](https://github.com/odroe/odroe/tree/main/sites/odroe.dev)，由 Odroe 的 Document、Press 与 SSG
构建。当前 `odroe.dev` 外部访问受 Cloudflare 526 SSL 错误阻塞，不宣称已
线上可用。
