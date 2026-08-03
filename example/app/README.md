# Odroe Full-stack App

这是由 Flutter CLI 创建的标准 Odroe 应用，展示显式 modules、文件路由、强类型
params/search、Server Function、typed SQL、语义 HTML、SSG 与 Flutter 首屏交接。
`/posts` 的有界游标分页和创建、以及 `/posts/42` 的详情组成一条真实纵向产品：Flutter
Infinite Query / Mutation → 生成的 named-record typed RPC → HTTP → Server →
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
在 `.odroe/app.sqlite3`。监听前读取 `migrations/*.sql` 并完成 pending migration，
每个请求只借用数据库，并在 `Server.close()` 时关闭。重启会保留已有数据；
`ODROE_SQLITE_PATH` 与 `ODROE_MIGRATIONS_PATH` 可分别覆盖数据库与 migration
路径，生产环境应把前者指向持久卷上的绝对可写路径。默认相对路径以 server
进程的当前目录为基准。Native dev 会监听该目录，新增或修改 SQL 后自动重启并
在监听前完成校验或应用。

`readSqliteMigrations(path)` 只接受顶层 `NNNN_snake_case.sql` 普通文件并按数字
排序；`SqliteDatabase.applyMigrations(...)` 把每个完整 SQL script 与 native
ledger 行放在同一事务。它在取得跨连接写锁后重新校验完整历史，并使用 SQLite
parser 执行 statement，不按分号切割。首次启动应用两条 migration；直接调用
runner 时返回 2，后续调用返回 0。已应用文件被编辑、删除、重命名或补插低版本
时会拒绝启动，而不是猜测或修复历史。
`Posts` projection 通过 `row.read(selection)` 解码完整的 `Post` 记录，不维护
容易随列顺序漂移的数字下标。`Post`、`PostPage`、`CreatePost` 与
`ListPostsInput` 放在客户端安全的
`lib/posts.dart`，route compiler 为输入、输出、列表和 stream item 生成对称
codec，不需要手写 JSON adapter。server 将 `limit` 限定在 `1..50`，按唯一
ID 使用严格 keyset predicate，读取 `limit + 1` 行后只返回 `items` 与可选
`nextCursor`。Flutter 的 `InfiniteQueryBuilder` 追加每一页，不会把整表一次
放入 RPC frame。列表还可用 typed `ids` 经 `isIn` 限定数据库行；空列表
表示不过滤，非空过滤最多接受 100 个 ID，并在 SQL 构造前拒绝超限输入。
创建使用单条 typed `INSERT ... RETURNING`，由数据库生成 ID 并返回完整 `Post`。
Native build 的 `--server-artifact` 指向完整 bundle root，默认是
`build/odroe/server`。入口为 `bin/server`（Windows 为 `bin/server.exe`），
运行所需的 native libraries 位于 `lib/`。本应用的 `odroe.yaml` 选择
`migrations`，因此 Native build 会验证这些文件并原字节复制到同一根目录的
`migrations/`；`--sqlite-migrations <path>` 可覆盖本次命令。从 bundle 根运行
`./bin/server`，部署时必须保留整个
目录；进程管理器也应把该根目录设为工作目录。若 history 外置，再用
`ODROE_MIGRATIONS_PATH` 指向其绝对路径。
构建预渲染时，同一选择固定 source，Odroe CLI 会把数据库覆盖为一次性临时文件，
结束后删除临时数据库，因而不会读取或改写开发数据库。初始 migration 使用幂等
建表与 seed，只用于接纳此前尚无 ledger 的未发布 Native starter；runner 不会为
任意既有 schema 猜测 baseline。

Cloudflare target 则为每次 Fetch invocation 包装 `DB` binding；表结构和种子数据
来自同一组可审查的 `migrations/*.sql`。Native 与 D1 各自维护 ledger；共享的是
append-only source history，不是假装共享连接或 runtime。已应用文件不得编辑、
删除或重命名，新变化必须新建更大编号。示例在本目录的 `package.json` 与
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

访问 `/posts?sort=newest`，加载下一个 typed cursor page，创建一条记录，再进入返回 ID 对应的详情页。Native
与本地 D1 都从共享历史得到 `Odroe post 42`；两者都必须完成
page → next page → create → refresh → read，未知 ID 返回 typed RPC 404，空标题返回受控 400
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
