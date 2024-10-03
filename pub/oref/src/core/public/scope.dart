import '../types/public.dart' as public;
import '../impls/scope.dart' as impl;
import '../impls/utils.dart';

/// Creates an effect scope.
public.Scope createScope([bool detached = false]) => impl.Scope(detached);

/// Returns the current active effect scope if there is one.
public.Scope? getCurrentScope() => impl.evalScope;

/// Registers a dispose callback on the current active effect scope.
void onScopeDispose(void Function() cleanup, [bool failSilently = false]) {
  if (impl.evalScope != null) {
    impl.evalScope!.cleanups.add(cleanup);
  } else if (dev && !failSilently) {
    warn('onScopeDispose() was called outside of an effect scope.');
  }
}
