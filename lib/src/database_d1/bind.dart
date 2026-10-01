import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Calls D1's variadic `bind` method without making the rest of the driver
/// dynamically dispatch JavaScript members.
JSObject bindD1Parameters(JSObject statement, List<JSAny?> parameters) {
  return statement.callMethodVarArgs<JSObject>('bind'.toJS, parameters);
}
