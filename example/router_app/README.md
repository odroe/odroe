# Router App

这是由 `flutter create --empty --platforms=web` 创建的标准 Flutter 应用，用于验证 Odroe 文件路由完整链路。Web 只是这个 fixture 的目标，不是 Odroe Router 的平台边界。

```sh
dart run odroe routes
flutter run -d chrome
```

`lib/routes.dart` 由 `lib/routes/` 生成并提交，用于验证编译结果稳定且应用可以直接分析、构建和运行。
