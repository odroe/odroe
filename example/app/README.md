# Odroe Full-stack App

这是由 Flutter CLI 创建的标准应用，展示 Odroe Router、Query、Server Function、SSR/SSG 与 Flutter 首屏交接。仓库只提交轻量 Web target 以控制体积；用户应用构建 Android、iOS、Web 或桌面端，始终由自己的 `flutter create/run/build` 决定。

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
```

`lib/routes.dart` 与 `lib/routes.server.dart` 都由 `lib/routes/` 生成；前者只包含客户端代码，后者拥有服务端 route、RPC binding 与 `createServer()`。
