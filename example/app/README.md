# Odroe Full-stack App

这是由 Flutter CLI 创建的标准 Odroe 应用，展示显式 modules、文件路由、强类型
params/search、Server Function、typed SQL、语义 HTML、SSG 与 Flutter 首屏交接。
`/posts/42` 是一条真实的纵向路径：Flutter page → Query → 生成的 typed RPC →
HTTP → Server → `DatabaseModule` → typed SQL。页面离开或显式取消 Query 时，
同一信号会终止 HTTP 请求，并为失败状态提供显式重试。

```sh
flutter pub get
dart run odroe generate
dart run odroe dev -- -d chrome
dart run odroe dev --server-only
dart run odroe build web
```

## One query, two database runtimes

共享的 route handler 只依赖 `package:odroe/database.dart`。`lib/server.dart` 用
条件导出选择平台入口：Native server 打开一份进程拥有的 in-memory SQLite，
监听前完成初始化，每个请求只借用它，并在 `Server.close()` 时关闭。
这是零配置、确定性的可运行示例，不是持久化或 migration 方案。

Cloudflare target 则为每次 Fetch invocation 包装 `DB` binding；表结构和种子数据
来自可审查的 `migrations/0001_posts.sql`。示例在本目录的 `package.json` 与
lockfile 中固定 Wrangler 4.118.0；`engines` 与 `devEngines` 会在 npm 安装、
运行脚本前要求 Node 22+ 与 npm 10.9+。Wrangler 不需要全局安装，也不会进入
Odroe 的 Dart 依赖图或应用产物。
本地验证 D1 路径：

```sh
flutter pub get
npm ci
dart run odroe build --server-target cloudflare web
npm run cloudflare:migrate:local
npm run cloudflare:dev
```

访问 `/posts/42?preview=true&tags=one&tags=two`。Native 返回
`SQLite post 42`，本地 D1 返回 `D1 post 42`；未知 ID 返回 typed RPC 404。
远端 migration 与 deploy 会修改平台状态，不属于上述本地命令。

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
