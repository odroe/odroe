import 'client.dart';
import 'managers.dart';
import 'mutation_state.dart';

/// Reactive facade that tracks the latest execution of one mutation kind.
final class MutationObserver<TData, TVariables, TOptimistic> {
  /// Creates an observer for [options] on [client].
  MutationObserver(this.client, this.options)
    : _state = MutationState<TData, TVariables, TOptimistic>.idle();

  /// The client used to execute mutations.
  final QueryClient client;

  /// The mutation definition observed by this object.
  final MutationOptions<TData, TVariables, TOptimistic> options;
  MutationState<TData, TVariables, TOptimistic> _state;
  final Set<void Function(MutationState<TData, TVariables, TOptimistic>)>
  _listeners = <void Function(MutationState<TData, TVariables, TOptimistic>)>{};
  QueryDispose? _removeMutation;

  /// The latest mutation state.
  MutationState<TData, TVariables, TOptimistic> get current => _state;

  /// Subscribes to mutation state changes and emits the current state.
  QueryDispose subscribe(
    void Function(MutationState<TData, TVariables, TOptimistic> state) listener,
  ) {
    _listeners.add(listener);
    listener(_state);
    return () => _listeners.remove(listener);
  }

  /// Starts the mutation with [variables].
  Future<TData> mutate(TVariables variables) {
    _removeMutation?.call();
    final mutation = client.mutationCache.build(client, options);
    _removeMutation = mutation.subscribe(_update);
    return mutation.execute(variables);
  }

  /// Detaches the current execution and restores idle state.
  void reset() {
    _removeMutation?.call();
    _removeMutation = null;
    _update(MutationState<TData, TVariables, TOptimistic>.idle());
  }

  void _update(MutationState<TData, TVariables, TOptimistic> value) {
    _state = value;
    for (final listener
        in List<
          void Function(MutationState<TData, TVariables, TOptimistic>)
        >.of(_listeners)) {
      listener(value);
    }
  }

  /// Releases subscriptions held by this observer.
  void dispose() {
    _removeMutation?.call();
    _removeMutation = null;
    _listeners.clear();
  }
}
