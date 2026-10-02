import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';

import 'counter_page.dart';
import 'greeting.dart';

final greeting = localGreeting();

Widget queryApp() => QueryClientProvider(
  child: WidgetsApp(
    color: const Color(0xff222222),
    builder: (_, _) => CounterPage(greeting: greeting),
  ),
);

void main() => runApp(queryApp());
