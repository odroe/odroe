import 'package:odroe/odroe.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';

final contextKey = ContextKey<String>('client');
final routeCapability = RouteCapability<String>('document');
final requestKey = RequestKey<String>('user');

void registerFixture(ModuleRegistry registry) {
  contextKey.provide(registry, 'client');
  contextKey.provideFactory(registry, () => 'lazy client');
}

void storeRequestFixture(RequestContext context) {
  requestKey.set(context, 'user');
}

final routeFixture = routeCapability.attach(
  AppRoute<NoParams, NoSearch, NoData>(),
  'document',
);
