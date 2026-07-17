# Start 研究记录

本记录约束 Odroe Start 的服务端、编译和 Flutter 交接边界。Start 是 Flutter 全栈元框架的一部分，不是 Dart HTTP server，也不是 Flutter Web 框架。

## 研究基线

- 仓库：`TanStack/router`
- commit：`0b178a79e2e872df0107bd7f0faa891c4c9815ef`
- 重点包：`start-client-core`、`start-server-core`、`start-plugin-core`、`start-static-server-functions`
- 重点源码：`createServerFn.ts`、`createMiddleware.ts`、`serverRoute.ts`、`createStartHandler.ts`、`server-functions-handler.ts`、`handleCreateServerFn.ts`、frame protocol 和 request/response utilities
- 重点文档：Server Functions、Server Routes、Execution Model、Middleware、Streaming、Static Server Functions

TanStack 当前把 Start 拆成多个 npm package 是发布和多前端适配的结果。Odroe 保留其内部职责边界，但所有产品 API 仍位于单一 `odroe` package 的多个 entrypoint 中。

## 核心结论

### Server Function 和 Server Route 是两个产品

Server Function：

- 只服务于同一个 Odroe App；
- 调用体验是强类型函数；
- 编译后客户端只有 RPC stub，服务端才保留 handler；
- 默认 same-origin，必须有 CSRF 防护；
- 框架负责参数、结果、错误、redirect、not-found 和 stream 的传输。

Server Route：

- 是公开 HTTP endpoint；
- 面向 webhook、第三方 API、文件和自定义协议；
- 用户直接处理 Request/Response；
- 支持完整 HTTP method、HEAD fallback 和 route middleware。

不能用 Server Function 冒充公开 API，也不能强迫 App 内数据调用手写 HTTP。

### 无编译步骤就没有可靠的 server-only 边界

TanStack 的编译器会：

1. 找到赋值给稳定变量名的 server function；
2. 用相对文件名和函数名生成稳定 ID；
3. 生成只含真实 handler 的 provider module；
4. 在 Flutter/client 产物里把 handler 替换成 RPC stub；
5. 生成 manifest，使服务端可按 ID 定位实现；
6. 对 server-only/client-only import 做构建期保护。

Dart 没有可依赖的同等 source transform，因此 Odroe 不假装同一 `server.dart` 可以安全进入 Flutter bundle。文件路由编译器必须生成两个目标：

- `routes.dart`：client-safe route tree、typed server-function refs；
- server manifest/bootstrap：导入 `server.dart` 的 route fragments、handlers 和真实 functions。

用户不写 ID、hash、registry 或 glue code。稳定 ID 由 route path、声明名和编译版本生成，仅作为内部传输细节。

### `server.dart` 是完整服务端 fragment

它不只是 loader 文件。每个 route 的 `server.dart` 可以声明：

- 最终 `route` fragment；
- loader；
- route middleware；
- 公开 HTTP method handlers；
- App 内 server functions/RPC；
- response metadata 或 route 级服务端策略。

`route.dart` 仍是 client/server 共享的 params、search、data 和 RPC 数据类型合同；`page.dart` 只包含 Flutter UI。不存在第二套前端，也不需要 `page.document.dart`。

### Middleware 需要一条链，而不是多个互不一致的拦截器

执行顺序固定为：

1. 全局 request middleware；
2. 父到子的 route middleware；
3. method 或 server-function middleware；
4. handler；
5. 反向返回。

Request middleware 处理所有进入 Start 的请求。Function middleware 可同时包裹客户端 RPC 和服务端 handler。客户端 context 默认不跨网络；显式发送的数据在服务端仍是不可信输入。

Odroe 使用 typed context keys 扩展请求上下文，避免公开 API 退化成任意字符串 Map。安全边界必须落在实际读取或修改数据的 function/handler 上，route guard 只能改善 UX，不能替代授权。

### Request/Response 必须 adapter-neutral

Start core 只认识自己的标准请求和响应：method、URI、headers、body stream、status。默认 Dart IO adapter 只是开箱即用的宿主，不能渗入 route、middleware、RPC、renderer 或 Query。

同一 handler 应可由 Dart IO、Relic、Cloudflare/Dart runtime、测试内存 adapter 或未来基础设施承载。

### Serialization 是协议，不是 JSON helper

协议至少需要：

- 可替换 codec/adapter registry；
- 常用 JSON-like 值的默认支持；
- 强类型 input/output codec；
- error、redirect、not-found 的独立 frame；
- raw response；
- cancellation；
- typed stream 和背压；
- 协议版本与 payload size 限制。

运行时 decode 同时承担边界验证。用户无需为了每个普通 record 再写一份手动 validator；自定义领域类型通过 codec 注册扩展。

### Start 与 Query 的交接是首屏协议

一次应用页面请求：

1. 匹配同一 AppRoute tree；
2. 创建请求级 QueryClient；
3. 执行父到子 middleware 和 loader；
4. loader 可 ensure/prefetch query，自动请求去重；
5. renderer 获得 route data、dehydrated Query 和文档 metadata；
6. HTML/SSG 输出可包含 SEO/GEO 可读内容和 Flutter bootstrap；
7. Flutter 加载后 hydrate 同一状态，后续导航由 Flutter Router 承接；
8. pending query/loader 可继续通过 stream frame 到达客户端。

Flutter 是否构建 Android、iOS、macOS、Windows、Linux、Web 由用户项目和 Flutter CLI 决定。Start 的 HTML/SEO 能力不能反向把 Odroe 定义成 Flutter Web 框架。

### CLI 是产品入口

- `dart run odroe dev`：编译并 watch routes/server manifest，启动 adapter-neutral Start host，并把 Flutter target 参数交给 Flutter CLI。
- `dart run odroe build`：生成路由与 server manifest，按用户选择构建 Flutter target 和 Start server artifact。
- `dart run odroe generate`：只执行确定性的代码生成，可用于编辑器和外部构建系统。
- `dart run odroe routes` 保留为精确子命令，但不是正常开发的主心智。

CLI 不要求用户手工组装 runtime，也不把临时 Dart 文件当测试策略。编译输出必须稳定、可诊断、可增量更新。

## Odroe API 决策

- `package:odroe/start.dart`：App 配置、server fragments/functions/routes、middleware、request/response、handler 和 Query/Router 集成。
- `ServerFunction<I, O>` 只表示服务端实现；生成的 `ServerFunctionRef<I, O>` 是 client-safe 调用合同。
- `StartTransport` 可替换，Flutter 端默认使用同源 HTTP transport；服务端内调用直接执行 handler，不做 loopback HTTP。
- `StartHandler` 是 `StartRequest -> Future<StartResponse>`，adapter 仅负责类型转换和 socket 生命周期。
- 默认安装 server-function same-origin/CSRF middleware；显式自定义全局 middleware 不应悄悄移除安全默认值。
- QueryClient 每请求创建；Flutter client 的 QueryClient 每个应用实例创建。

## 明确不做

- 不基于某个数据库、ORM、HTTP server 或部署平台设计公开 API。
- 不把 Start 缩成 loader registry 或简化 Serverpod。
- 不让 Flutter bundle import `server.dart`。
- 不要求 annotation、`part`、build_runner 或用户维护 manifest。
- 不让 `routes.dart` 只是路径清单；它必须是可直接运行的类型安全产品入口。
- 不为 SEO 再造第二套页面组件树。

