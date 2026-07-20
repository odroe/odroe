import '../app/context.dart';
import '../app/key.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'client.dart';
import 'managers.dart';

/// The application context key used to read the registered [QueryClient].
const queryClientKey = ContextKey<QueryClient>('queryClient');

/// Installs a Query client into an application context.
class QueryClientModule extends Module {
  /// Creates a module with an owned or caller-owned client.
  QueryClientModule({QueryClient? client})
    : client = client ?? QueryClient(),
      _ownsClient = client == null;

  /// Creates a request-scoped server Query client.
  QueryClientModule.server()
    : client = QueryClient(
        options: const QueryClientOptions(
          environment: QueryEnvironment(isServer: true),
        ),
      ),
      _ownsClient = true;

  /// The client registered by this module.
  final QueryClient client;

  final bool _ownsClient;

  @override
  void register(ModuleRegistry registry) {
    registry.provide(queryClientKey, client);
  }

  @override
  void dispose(AppContext context) {
    if (_ownsClient) client.clear();
  }
}
