# Query 研究记录

本记录用于约束 Odroe Query 的产品边界。它不是 TanStack Query 的 Dart 翻译，也不以 React hooks 为 API 模板；研究对象是其状态模型、并发语义和长期验证过的用户心智。

## 研究基线

- 仓库：`TanStack/query`
- commit：`97db5d244715642fb63d9ce78566aa632cdfdc07`
- `@tanstack/query-core`：`5.101.2`
- 重点源码：`query.ts`、`queryClient.ts`、`queryObserver.ts`、`mutation.ts`、`retryer.ts`、`infiniteQueryBehavior.ts`、`hydration.ts`、`query-persist-client-core`
- 重点测试：上述模块的同名测试，以及 cancellation、offline、hydration、persistence 测试

## 核心结论

### Query 不是缓存函数

一个 query 是长期存在的异步 server-state 状态机。缓存只负责按稳定 key 保存状态机实例。

状态必须由两个正交维度组成：

- `status`：`pending`、`success`、`error`，描述数据结果。
- `fetchStatus`：`idle`、`fetching`、`paused`，描述当前传输活动。

因此“首次离线等待”是 `pending + paused`，“后台刷新失败但仍有旧数据”是 `error + idle + hasData`。把它们压成一个 `loading/error/data` 会丢失真实语义。

### 一份 key 只对应一个并发入口

- 同 key 的并发 fetch 默认复用同一 Future。
- 已有数据时显式 refetch 可以取消旧请求再启动新请求。
- query function 读取 cancellation token 后，最后一个 observer 卸载会取消传输并回滚到 fetch 前状态。
- 未读取 token 时允许请求完成并写入缓存，以便短暂离开页面后复用结果。

取消不是普通错误。它需要独立携带 `silent` 和 `revert` 语义。

### fresh、stale、invalidated、static 不可混为一谈

- 默认 `staleTime` 为零；数据写入后立即可在合适时机后台刷新。
- `staleTime: null` 表示时间不会使数据过期，但显式 invalidate 仍生效。
- `static` 表示应用生命周期内不可变，连 invalidate 和 `always` refetch 触发器也不应自动刷新。
- inactive query 默认保留五分钟再 GC；有 observer 或正在 fetch 时不可回收。
- invalidation 先标记，再按 filter 和 active 状态决定是否 refetch。

### Observer 是响应式产品边界

cache/query 不依赖 UI。Observer 负责：

- 首次订阅时按 stale、mount policy 决定 fetch；
- key/options 改变时切换 query；
- stale timer、polling、focus/reconnect refetch；
- 派生 `isLoading`、`isRefetching`、`isPaused`、`isLoadingError`、`isRefetchError`；
- 抑制没有实际变化的通知。

React 的属性访问追踪是框架适配，不应照搬。Flutter 使用 observer 加 selector，只在选中结果变化时 rebuild。

### Retry 必须理解运行环境

- 默认客户端查询失败重试三次，服务端不重试。
- 默认退避为指数增长并封顶 30 秒。
- `online`：离线时首次执行和重试都暂停。
- `always`：忽略网络状态，适用于本地存储或非网络 Future。
- `offlineFirst`：允许第一次执行命中 HTTP/本地缓存，失败后的重试再等待联网。
- 暂停不改变 query 的数据 `status`，只改变 `fetchStatus`。

### Mutation 是独立状态机，但共享调度和持久化

Mutation 需要完整的 `idle/pending/success/error` 生命周期，以及：

- `onMutate` 在副作用前执行并返回 optimistic context；
- 全局与局部 `onSuccess/onError/onSettled` 有稳定顺序；
- 同 scope 的 mutation 串行执行，不同 scope 并行；
- 离线 mutation 可暂停、dehydrate、恢复后续跑；
- 每次 mutate 创建新的 mutation 实例，observer 只跟踪最近一次调用。

Optimistic update 不需要第二套状态系统。`onMutate` 直接通过同一个 `QueryClient` cancel、读取和写回 query，失败时使用 context 回滚。

### Infinite Query 不是第二份缓存

Infinite query 使用普通 query 状态机和一个 behavior：

- 数据为 `pages + pageParams`；
- next/previous fetch 在同一个 cache entry 上运行；
- stale refetch 从第一页开始顺序刷新，避免旧 cursor 导致重复或跳项；
- `maxPages` 同时限制内存和之后的 refetch 成本；
- 同一 infinite query 默认只允许一个进行中的 fetch。

### Hydration 以时间为仲裁依据

- 默认只 dehydrate 成功 query 和暂停 mutation。
- hydration 不得用旧数据覆盖客户端更新的数据。
- 恢复普通状态时强制 `fetchStatus: idle`，避免永远卡在 fetching。
- 正在进行的 query 可以携带 pending channel，供 Start streaming 接续。
- 服务端每个请求必须创建独立 QueryClient，禁止跨用户共享缓存。

### Persistence 是可替换边界

持久化只依赖 `save/restore/remove`，不绑定 SQLite、文件系统或 SharedPreferences。持久化载荷必须包含：

- 写入时间；
- schema/cache buster；
- dehydrated state。

恢复时先检查 max age 和 buster；损坏数据应删除。只订阅 cache 的 added/removed/updated，observer 事件不应触发磁盘写入，并需要合并短时间内的连续更新。

## Odroe API 决策

- `package:odroe/query_core.dart`：纯 Dart 状态机、client、observer、mutation、infinite、hydration、persistence。
- `package:odroe/query.dart`：在 core 之上增加 Flutter provider、builder 和 selector。
- `QueryKey` 由字符串 namespace 和 JSON-like parts 组成；Map key 顺序不影响 identity，List 顺序影响 identity；不接受无法稳定编码的对象。
- `QueryOptions<T>` 是可复用、强类型的 query contract；Flutter widget 不是 query 定义位置。
- cancellation 使用 Odroe 自己的 `QueryCancelToken`，不绑定 HTTP client。
- focus、online、clock、timer 都是可替换基础设施；默认不引入 connectivity 等平台插件。
- QueryClient 支持全局 defaults 和按 key prefix 的 defaults，但不会制造第二套配置 DSL。
- Start loader 使用请求级 QueryClient 预取，并通过同一 hydration format 交给 Flutter。

## 明确不做

- 不把 server state 混进 Flutter 本地 widget state。
- 不以 `Map<String, dynamic>` 作为公开 query 定义 API。
- 不为 SQLite 或任何数据库提供特权路径。
- 不复制 React hooks、Proxy property tracking 或 JS 的 `undefined` 偶然语义。
- 不用 code generation 才能创建普通 query；文件编译只负责 Start/Router 边界。

