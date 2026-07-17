import 'package:odroe/start.dart';

import 'route.dart' as definition;

final class LocalValue {
  const LocalValue(this.value);

  final int value;
}

final route = definition.route.server();

final exposeLocal = ServerFunction<LocalValue, int>(
  handler: (context) => context.data.value,
);
