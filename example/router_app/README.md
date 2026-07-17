# Odroe App Fixture

这是由 Flutter CLI 创建的标准应用，用于验证 Odroe Router、Query、Start、Server Function 与双目标生成完整链路。这个 fixture 只保留一个轻量 Flutter target 以控制仓库体积；用户应用构建什么 target 始终由自己的 `flutter create/run/build` 决定。

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
```

`lib/routes.dart` 与 `lib/routes.server.dart` 都由 `lib/routes/` 生成并提交，用于验证 client 不导入 `server.dart`、server manifest 可执行、生成结果稳定且应用可直接分析、构建和运行。
