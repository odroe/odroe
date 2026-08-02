# Odroe Full-stack App

这是由 Flutter CLI 创建的标准 Odroe 应用，展示显式 modules、文件路由、强类型
params/search、Server Function、typed SQL、语义 HTML、SSG 与 Flutter 首屏交接。
`/posts` 的列表和创建、以及 `/posts/42` 的详情组成一条真实纵向产品：Flutter
Query / Mutation → 生成的 named-record typed RPC → HTTP → Server →
`DatabaseModule` → typed SQL。页面离开或显式取消 Query 时，同一信号会终止
读取请求；创建完成后只失效帖子列表并从服务端真值刷新。

```sh
flutter pub get
dart run odroe generate
dart run odroe dev -- -d chrome
dart run odroe dev --server-only
dart run odroe build web
```

## One query, two database runtimes

共享的 route handler 只依赖 `package:odroe/database.dart`。`lib/server.dart` 用
条件导出选择平台入口：Native server 打开一份进程拥有的文件 SQLite，默认保存
在 `.odroe/app.sqlite3`。监听前完成幂等 bootstrap，每个请求只借用它，并在
`Server.close()` 时关闭。重启会保留已有数据；`ODROE_SQLITE_PATH` 可覆盖路径，
生产环境应指向持久卷上的绝对可写路径。默认相对路径以 server 进程的当前目录
为基准。

Native 的 `CREATE TABLE IF NOT EXISTS` 与公共 typed SQL
`insertOnConflictDoNothing(..., target: [posts.id])` 只是固定初始 schema 的
starter bootstrap，不会修改已有表结构。`Posts` projection 解码完整的
`Post` 记录。`Post`、`CreatePost` 与 `ListPostsInput` 放在客户端安全的
`lib/posts.dart`，route compiler 为输入、输出、列表和 stream item 生成对称
codec，不需要手写 JSON adapter。列表可用 typed `ids` 经 `isIn` 限定数据库行；
空列表表示不过滤，非空过滤最多接受 100 个 ID，并在 SQL 构造前拒绝超限输入。
创建使用单条 typed `INSERT ... RETURNING`，由数据库生成 ID 并返回完整 `Post`。
Native schema 演进需要应用自己的 migration 流程。构建预渲染时，Odroe CLI 会把
`ODROE_SQLITE_PATH` 覆盖为一次性临时文件，并在结束后删除，因而不会读取或改写
开发数据库。

Cloudflare target 则为每次 Fetch invocation 包装 `DB` binding；表结构和种子数据
来自可审查的 `migrations/0001_posts.sql`。示例在本目录的 `package.json` 与
lockfile 中固定 Wrangler 4.118.0；`engines` 与 `devEngines` 会在 npm 安装、
运行脚本前要求 Node 22+ 与 npm 10.9+。Wrangler 不需要全局安装，也不会进入
Odroe 的 Dart 依赖图或应用产物。
本地验证 D1 路径：

```sh
flutter pub get
npm ci
dart run odroe build --no-server web
npm run cloudflare:migrate:local
npm run cloudflare:dev
```

`cloudflare:dev` 进入 Odroe 的 Cloudflare server-only 开发模式：每次启动先从
当前 Dart route 编译 Worker，成功后原子替换 server JavaScript，再调用本项目
锁定的 Wrangler。后续 server 源码变化会自动 reload；成功启动后的生成或编译
失败会继续运行上一份可用 Worker，修复后自动恢复。首次 route 生成或编译失败
会退出。Flutter Web/static assets 不在这条 server-only watch 中，UI 变化后再次
执行 `dart run odroe build --no-server web`。

访问 `/posts?sort=newest`，创建一条记录，再进入返回 ID 对应的详情页。Native
初始包含 `SQLite post 42`，本地 D1 初始包含 `D1 post 42`；两者都必须完成
list → create → list → read，未知 ID 返回 typed RPC 404，空标题返回受控 400
且不能新增记录。远端 migration 与 deploy 会修改平台状态，不属于上述本地命令。

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
