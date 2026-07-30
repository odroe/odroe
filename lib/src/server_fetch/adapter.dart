import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../server/invocation.dart';
import 'http.dart';

/// Opaque Fetch runtime bindings for one server invocation.
final class FetchBindings {
  /// Wraps the raw JavaScript environment object.
  const FetchBindings(this.raw);

  /// The environment object passed to the Fetch handler.
  final JSObject raw;
}

/// Registers [handler] as `globalThis.__odroeFetch`.
void exportFetchHandler(ServerInvocationHandler handler) {
  _globalThis.__odroeFetch =
      ((web.Request request, JSObject bindings, _ExecutionContext context) {
        final invocation = ServerInvocation(
          bindings: FetchBindings(bindings),
          waitUntil: (task) => context.waitUntil(task.toJS),
        );
        return handleFetchInvocation(handler, request, invocation).toJS;
      }).toJS;
}

@JS('globalThis')
external _GlobalThis get _globalThis;

extension type _GlobalThis(JSObject _) implements JSObject {
  external set __odroeFetch(JSFunction value);
}

extension type _ExecutionContext(JSObject _) implements JSObject {
  external void waitUntil(JSPromise<JSAny?> promise);
}
