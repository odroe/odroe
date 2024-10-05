/// A reference class that holds a nullable value of type [T].
///
/// This class is used internally for managing typed references.
final class EvalReference<T> {
  /// Private constructor to prevent direct instantiation.
  EvalReference._();

  /// The nullable value held by this reference.
  T? value;
}

final _evals = <WeakReference<EvalReference>>[];

/// Find or creates a typed eval reference.
///
/// This function manages a pool of [EvalReference] objects, creating new ones
/// when necessary and reusing existing ones when possible. It also performs
/// cleanup of unused references.
///
/// Returns an [EvalReference<T>] that can be used to store and retrieve values of type [T].
EvalReference<T> findOrCreateEval<T>() {
  _evals.removeWhere((ref) => ref.target == null);
  for (final WeakReference(:target) in _evals) {
    if (target is EvalReference<T>) {
      return target;
    }
  }

  final eval = EvalReference<T>._();
  _evals.add(WeakReference(eval));

  return eval;
}

final _marked = Expando<Expando>();
final _cached = Expando<EvalReference>();

/// Find or creates an [Expando<T>] object.
///
/// This function creates or retrieves an [Expando] object that serves as a weak map container.
/// It supports two modes of operation:
///
/// 1. Unmarked mode (when [mark] is null):
///    - Searches for an existing [Expando] of type [T] in the [_typed] list.
///    - If found, returns the existing [Expando].
///    - If not found, creates a new [Expando<T>], adds it to [_typed], and returns it.
///
/// 2. Marked mode (when [mark] is provided):
///    - Uses the [mark] to retrieve or create an [Expando] from [_marked].
///    - If the retrieved [Expando] matches type [T], returns it.
///    - If the types don't match, throws a [StateError].
///
/// [T] must be a non-nullable object type.
///
/// [mark] is an optional object used to identify the [Expando] in marked mode.
///
/// Returns an [Expando<T>] that can be used as a weak map container.
///
/// Throws a [StateError] if the [mark] is already associated with a different type.
Expando<T> findOrCreateExpando<T extends Object>([Object? mark]) {
  if (mark == null) {
    final ref = findOrCreateEval<Expando<T>>();
    final expando = ref.value ??= Expando<T>();

    // Cache the reference to avoid creating a new one.
    _cached[expando] = ref;
    return expando;
  }

  final expando = _marked[mark] ??= Expando<T>();
  if (expando is Expando<T>) {
    return expando;
  }

  throw StateError('Invalid mark, the mark is already used for another type.');
}
