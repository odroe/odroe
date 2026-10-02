import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';

import 'greeting.dart';
import 'routed_app.dart';

final greeting = localGreeting();

Widget routedApp() => QueryClientProvider(child: RoutedApp(greeting: greeting));

void main() => runApp(routedApp());
