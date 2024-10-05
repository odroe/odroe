import '../types/public.dart' as public;
import '../impls/scope.dart' as impl;
import '../impls/utils.dart';

/// Creates an effects scope.
///
/// An effect scope is used to group and manage side effects in a structured way.
/// The [detached] parameter determines if the scope is detached from its parent.
public.Scope createScope([bool detached = false]) => impl.Scope(detached);

/// Returns the current active effects scope if there is one.
///
/// This function is useful for accessing the current scope in nested operations.
public.Scope? getCurrentScope() => impl.evalScope;

/// Registers a dispose callback on the current active effects scope.
///
/// The [cleanup] function will be called when the current scope is disposed.
/// If [failSilently] is true, it won't warn when called outside of a scope.
void onScopeDispose(void Function() cleanup, [bool failSilently = false]) {
  if (impl.evalScope != null) {
    impl.evalScope!.cleanups.add(cleanup);
  } else if (dev && !failSilently) {
    warn('onScopeDispose() was called outside of an effect scope.');
  }
}
