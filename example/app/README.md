# Odroe Full-stack App

这是由 Flutter CLI 创建的标准 Odroe 应用，展示显式 modules、文件路由、强类型 params/search、Server Function、语义 HTML、SSG 与 Flutter 首屏交接。`/posts/:postId` 的 Flutter 页面通过 Query 调用生成的 RPC ref；页面离开或显式取消 Query 时，同一信号会终止 HTTP 请求，并为失败状态提供显式重试。Flutter 构建 Android、iOS、Web 或桌面端，始终由应用自己的 Flutter CLI 目标决定。

```sh
dart run odroe generate
dart run odroe dev -- -d chrome
dart run odroe dev --server-only
dart run odroe build web
```

显式选择 Web device 后，开发代理会让页面和 RPC 使用同一 origin。当前
checkout 只提交 Web runner；运行原生目标前，先添加所需 Flutter runner，
例如：

```sh
flutter create --platforms=android .
flutter devices

device_id='emulator-5554'
api_origin='http://10.0.2.2:3000'
dart run odroe dev --port 3000 -- \
  -d "$device_id" \
  --dart-define="ODROE_API_ORIGIN=$api_origin"
```

将 `device_id` 改为 `flutter devices` 返回的标识。Android emulator 的宿主机
地址通常是 `10.0.2.2`；桌面端和 iOS Simulator 可用 `127.0.0.1`。真机改用
开发机局域网地址，并给 `odroe dev` 添加 `--host 0.0.0.0`。生产构建应传入
已部署的 HTTPS origin。

`lib/main.dart` 手动选择 Query、RPC、Document 与 Router modules。`lib/routes.dart` 与 `lib/routes.server.dart` 由 `lib/routes/` 生成；前者只包含客户端代码，后者拥有 server route、RPC binding 与可组合的 `createServer()`。
