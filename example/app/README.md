# Odroe Full-stack App

这是由 Flutter CLI 创建的标准 Odroe 应用，展示显式 modules、文件路由、强类型 params/search、Server Function、语义 HTML、SSG 与 Flutter 首屏交接。Flutter 构建 Android、iOS、Web 或桌面端，始终由应用自己的 Flutter CLI 目标决定。

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
dart run odroe build web
```

`lib/main.dart` 手动选择 Query、RPC、Document 与 Router modules。`lib/routes.dart` 与 `lib/routes.server.dart` 由 `lib/routes/` 生成；前者只包含客户端代码，后者拥有 server route、RPC binding 与可组合的 `createServer()`。
