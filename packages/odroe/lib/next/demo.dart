import 'package:flutter/material.dart';

import 'runtime/component.dart';
import 'runtime/fire.dart';
import 'runtime/reversal.dart';
import 'runtime/setup.dart';

// 推荐类型语法，自身引用自身，Dart 无法走动推断类型！
final Component<String?> sayHello = setup((props) {
  return () => props != null
      ? fire(() => Text(props)) // fire 函数用于将 Widget 转换为 Component
      : sayHello('Hello, input your name!');
});

// setup.z 用于创建零参数 component
final app = setup.z(() {
  return () => fire(() => MaterialApp(
        title: "App",
        home: reversal(sayHello(null)),
      ));
});

void main(List<String> args) {
  // reversal 函数用于将 Component 降级为 Widget
  runApp(reversal(app.zero));
}
