# TanStack Start 研究记录

TanStack Start 是 Odroe 研究全栈执行模型的对象，不是 Odroe 的产品名或独立层。Odroe 本身是完整 Flutter 全栈框架。

## 研究基线

- 仓库：`TanStack/router`
- commit：`0b178a79e2e872df0107bd7f0faa891c4c9815ef`
- 重点包：`start-client-core`、`start-server-core`、`start-plugin-core`、`start-static-server-functions`
- 重点源码：`createServerFn.ts`、`createMiddleware.ts`、`serverRoute.ts`、`createServerHandler.ts`、`server-functions-handler.ts`、`handleCreateServerFn.ts`、frame protocol 与 request/response utilities
- 重点文档：Server Functions、Server Routes、Execution Model、Middleware、Streaming、Static Server Functions

TanStack Start 被拆成多个 npm package，是其发布方式和多前端适配的结果。Odroe 保留必要的职责边界，但产品仍是一个 `odroe` package；完整应用使用 `odroe.dart`，独立能力使用对应入口。

## 核心结论

### Server Function 与 Server Route 是两个产品能力

Server Function：

- 只服务同一个 Odroe App；
- 调用体验是强类型函数；
- client 产物只有 RPC ref，server 产物保留 handler；
- Web 默认 same-origin，并校验 origin；
- 框架传输参数、结果、错误、redirect、not-found 与 stream。

Server Route：

- 是公开 HTTP endpoint；
- 面向 webhook、第三方 API、文件与自定义协议；
- 用户直接处理 `ServerRequest` 与 `ServerResponse`；
- 支持 HTTP method、HEAD fallback 与 route middleware。

不能用 Server Function 冒充公开 API，也不应迫使 App 内部调用手写 HTTP。

### Server-only 边界必须由编译目标保证

TanStack Start 的编译器会：

1. 找到稳定命名的 server function；
2. 用相对文件名与声明名生成稳定 ID；
3. 生成只包含真实 handler 的 server provider；
4. 在 client 产物中留下 RPC stub；
5. 生成 server manifest；
6. 保护 server-only/client-only import。

Dart 没有可依赖的同等 source transform，因此 Odroe 不让同一份 route `server.dart` 进入 Flutter bundle。文件路由编译器生成两个目标：

- `lib/routes.dart`：client-safe route tree、typed destination 与 RPC refs；
- `lib/routes.server.dart`：server route tree、function bindings 与 `createServer()`。

用户不写 ID、registry、hash 文件或胶水代码。稳定 ID 只是内部传输细节。

### `server.dart` 是完整服务端 route

每个 route 的 `server.dart` 可以声明：

- 最终服务端 `route`；
- loader；
- route middleware；
- 公开 HTTP method handler；
- App 内 RPC function。

`route.dart` 是 client/server 共享的 params、search、data 与 RPC 数据类型合同；`page.dart` 只包含 Flutter UI。不存在第二套前端，也不需要 `page.document.dart`。

### Middleware 只有一条执行链

执行顺序固定为：

1. 全局 request middleware；
2. 父到子的 route middleware；
3. function 或 method handler middleware；
4. handler；
5. 反向返回。

`ContextKey<T>` 扩展 request-scoped context，避免公开 API 退化为字符串 Map。授权必须位于真实读写数据的 function 或 handler；route guard 只能改善客户端体验。

### Request/Response 必须 adapter-neutral

`package:odroe/server.dart` 只依赖标准化的 method、URI、headers、body stream 与 status。Dart IO 只是 `server_io.dart` 提供的默认宿主，不能渗入 route、middleware、RPC、renderer 或 Query。

同一个 `OdroeServer.handler` 可以由 Dart IO、Relic、其他 Dart runtime、测试内存 adapter 或未来基础设施承载。

### Serialization 是协议

协议需要覆盖：

- 可替换的 `SerializationAdapter<T>`；
- 常见 JSON-like value 与内置 Dart value；
- 强类型 input/output decoder；
- error、redirect 与 not-found frame；
- raw response；
- typed stream。

Serializer 恢复 wire type，不替代授权和领域校验。普通用户不维护另一份协议 registry。

### Query 交接属于完整应用首屏

一次页面请求：

1. 匹配同一棵 route tree；
2. 创建 request-scoped `QueryClient`；
3. 执行 middleware 与 loader；
4. loader 可以预取 Query，并自动去重；
5. renderer 获得 route data、dehydrated Query 与 document metadata；
6. HTML/SSG 输出 SEO/GEO 可读内容与可选 Flutter bootstrap；
7. Flutter 恢复同一状态，后续导航由 `OdroeRouter` 承接。

Flutter 构建 Android、iOS、macOS、Windows、Linux 或 Web，由用户项目与 Flutter CLI 决定。HTML/SEO 能力不能把 Odroe 定义成 Flutter Web 框架。

### CLI 是正常产品入口

- `dart run odroe dev`：编译并 watch route targets，启动 Odroe server，并把 Flutter target 参数交给 Flutter CLI；
- `dart run odroe build`：生成 route targets，构建 server artifact，并按用户选择构建 Flutter target；
- `dart run odroe generate`：只执行代码生成；
- `dart run odroe generate --watch`：只监听并生成 route targets；正常开发直接使用 `dev`。

CLI 不要求用户手动组装 runtime，也不把临时 Dart 文件当产品流程。

## Odroe API 决策

- `package:odroe/odroe.dart`：完整 Flutter App，直接组合 Query、Router、RPC 与首屏交接；
- `package:odroe/rpc.dart`：独立 client、refs、transport 与 serialization；
- `package:odroe/server.dart`：adapter-neutral runtime、request/response、middleware、server functions 与 server routes；
- `package:odroe/server_io.dart`：Dart IO host 与 prerenderer；
- `ServerFunction<I, O>` 是 server implementation，生成的 `ServerFunctionRef<I, O>` 是 client-safe 调用合同；
- `RpcTransport` 可替换，Web 默认同源，原生 App 传入 server URI；
- `ServerHandler` 是 `ServerRequest -> Future<ServerResponse>`；
- 每个 HTTP request 创建独立 `QueryClient`，每个 Flutter App context 创建一个应用级 `QueryClient`。

## 明确不做

- 不基于数据库、ORM、HTTP server 或部署平台设计公开 API；
- 不把 Odroe server 缩成 loader registry 或简化 Serverpod；
- 不让 Flutter bundle import route `server.dart`；
- 不要求 annotation、`part`、build_runner 或用户维护 manifest；
- 不让 `routes.dart` 只是路径清单；
- 不为 SEO 再造第二套页面组件树。
