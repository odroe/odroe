import 'package:flutter/widgets.dart';

import '../app/context.dart';
import '../app/registry.dart';
import '../app_flutter/binding.dart';
import '../query/module.dart';
import 'provider.dart';

/// Installs Query into an application and its Flutter widget tree.
final class QueryModule extends QueryClientModule {
  /// Creates a Query module.
  ///
  /// When [client] is omitted, the module creates and owns a client. A supplied
  /// client remains owned by the caller and is not cleared on disposal.
  QueryModule({super.client});

  @override
  void register(ModuleRegistry registry) {
    super.register(registry);
    registry.bind(const _QueryFlutterBinding());
  }
}

final class _QueryFlutterBinding extends FlutterBinding {
  const _QueryFlutterBinding();

  @override
  Widget wrap(AppContext context, Widget child) =>
      QueryClientProvider(client: context.read(queryClientKey), child: child);
}
