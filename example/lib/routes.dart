import 'package:example/pages/counter.dart';
// import 'package:example/pages/home.dart';
import 'package:flutter/widgets.dart';

const initialRoute = '/';
final routes = <String, WidgetBuilder>{
  initialRoute: (context) => counter(),
};