import 'package:example/home.dart';
import 'package:example/pages/counter.dart';
import 'package:example/pages/hello.dart';
import 'package:example/pages/timer.dart';
import 'package:example/pages/todo.dart';
import 'package:flutter/widgets.dart';

const initialRoute = '/';
final routes = <String, WidgetBuilder>{
  initialRoute: (context) => home(),
  '/counter': (context) => counter(),
  '/timer': (context) => timer(),
  '/todo': (context) => todo(),
  '/hello': (context) => hello(),
};
