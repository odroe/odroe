# Document SSR/SSG 研究记录

本记录约束 Odroe 的语义 HTML、SEO/GEO、Flutter 接管与静态生成。Document 不是把 Flutter widget 翻译成 DOM，也不是要求用户维护第二套前端。

## 源码与官方资料

- [TanStack Router 与 TanStack Start](https://github.com/TanStack/router/tree/31a634d84ecf393dfb95adcf713fd5f1a13ab347)：route match 的 head 合并、SSR hydration、prerender queue、静态路由发现与真实 preview server 请求；
- [TanStack Query](https://github.com/TanStack/query/blob/97db5d244715642fb63d9ce78566aa632cdfdc07/packages/query-core/src/hydration.ts)：成功 Query 默认脱水，客户端只接受更新的快照，恢复时 fetch 状态回到 idle；
- [Nitro](https://github.com/nitrojs/nitro/blob/bfc2f5ef445494cec0f61ef3fe43ece4956dc14d/src/prerender/prerender.ts) 与 [Nuxt prerender](https://nuxt.com/docs/4.x/getting-started/prerendering)：构建真实 server 后请求路由、并发生成、站内链接抓取、输出安全、失败即构建失败；
- [Nuxt Content LLM integration](https://content.nuxt.com/docs/integrations/llms)：内容先形成可渲染 AST，同一内容可输出页面与 LLM/GEO 文本；
- [VitePress SSR compatibility](https://vitepress.dev/guide/ssr-compat.html)：构建期 SSR 产生静态 HTML，浏览器专属逻辑与生成阶段明确隔离；
- [Flutter Web initialization](https://docs.flutter.dev/platform-integration/web/initialization)：`flutter_bootstrap.js` 是正式加载入口；DevFS 与应用 HTML 可以通过同一 origin 协作，Flutter 首帧后再接管可见界面。

研究使用的上游源码位于临时 checkout，不进入 Odroe 仓库，也不成为运行时依赖。

## 产品边界

一个 route 可以贡献两种互补输出：

1. `RouteDocument`：平台中立、语义化、可被爬虫和 LLM 直接读取的 HTML；
2. `page.dart`：可选的 Flutter UI。

只有 Document 时，它就是纯 HTML route。两者同时存在时，Odroe server 首次请求输出 Document、loader/Query handoff 与 Flutter bootstrap；Flutter 第一帧后隐藏辅助 Document DOM，后续 Flutter 路由继续复用首屏数据。是否加载 Flutter 由当前匹配终点决定，不因应用内其他 route 存在 `page.dart` 而污染纯 HTML route。Flutter 原生目标只使用 page，不需要 DOM。

Document 位于 `route.dart`，不增加 `page.document.dart`。它与 params、search、loader data 共用同一强类型 route contract。父到子路由分别贡献 head 和 body；深层 title/meta/link 覆盖同 key 的祖先值，body 通过 `HtmlOutlet` 组合。

## 安全与性能约束

- 文本和属性默认转义；tag 与 attribute name 属于应用源码中的受信任结构，不接受用户内容；
- 不提供默认 raw HTML 逃逸口，内容系统应把 Markdown 解析为受控 AST；
- JSON-LD 使用 JSON 编码并转义 script terminator；
- document builders 在 loader 完成后并行执行，不产生隐藏的数据 waterfall；
- Query handoff 只服务 Flutter 混合页面；纯 HTML 不发送不需要的 loader/cache payload；
- 混合页面显式输出 base URL，保证嵌套 SSR/SSG 地址仍从正确位置加载 Flutter 产物；
- SSG 不直接调用另一套 renderer，而是请求构建后的真实 Odroe server；
- 预渲染只写站内、无 query、无 traversal 的 HTML route；
- 静态 route 自动枚举，动态 route 由真实 HTML 链接发现；并发和 timeout 是直接参数，非成功响应立即终止构建，不引入 retry/result wrapper、清单或 hash 合同。

## CLI 决策

- `odroe dev -- -d chrome`：浏览器打开 Odroe server origin；服务端提供 SSR HTML，并同源代理 Flutter DevFS、SSE 调试与资源；
- 其他 Flutter target：Odroe server 与 `flutter run` 并行，target 仍完全交给 Flutter CLI；
- `odroe build -- web --release`：生成 route targets，构建 Odroe server 与 Flutter Web，再请求真实 server 完成 SSG；
- 没有任何 `page.dart`/`shell.dart` 的纯 Document 应用：`odroe dev` 不启动 Flutter，`odroe build` 直接输出静态 HTML；
- `public/` 原样复制到静态输出；框架不生成站点 CSS。

## 后续提取边界

当前 renderer、crawler、静态输出和 DevFS proxy 都属于 Odroe 产品实现。只有在网站、Press 和外部宿主经过重复真实使用后，才考虑提取更通用的 HTML/runtime 基础设施；现在不提前制造新的底层生态。
