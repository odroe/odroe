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

```dart
final statement = BoundSql.parts(
  <String>['SELECT "title" FROM "posts" WHERE "id" = ', ''],
  <SqlValue>[sqlInt.encode(42)],
  kind: SqlStatementKind.rowReturning,
);
final manualTitles = await database.query(
  statement,
  (row) => row.read(0, sqlText),
);
```

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

可运行应用见 [`example/app`](example/app)。官网源码与正式文档位于
[`sites/odroe.dev`](sites/odroe.dev)，由 Odroe 的 Document、Press 与 SSG
构建。当前 `odroe.dev` 外部访问受 Cloudflare 526 SSL 错误阻塞，不宣称已
线上可用。
