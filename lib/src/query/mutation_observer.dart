// ignore_for_file: public_member_api_docs

import 'client.dart';
import 'managers.dart';
import 'mutation_state.dart';

/// Reactive facade that tracks the latest execution of one mutation kind.
final class MutationObserver<TData, TVariables, TOptimistic> {
  MutationObserver(this.client, this.options)
    : _state = MutationState<TData, TVariables, TOptimistic>.idle();

  final QueryClient client;
  final MutationOptions<TData, TVariables, TOptimistic> options;
  MutationState<TData, TVariables, TOptimistic> _state;
  final Set<void Function(MutationState<TData, TVariables, TOptimistic>)>
  _listeners = <void Function(MutationState<TData, TVariables, TOptimistic>)>{};
  QueryDispose? _removeMutation;

  MutationState<TData, TVariables, TOptimistic> get current => _state;

  QueryDispose subscribe(
    void Function(MutationState<TData, TVariables, TOptimistic> state) listener,
  ) {
    _listeners.add(listener);
    listener(_state);
    return () => _listeners.remove(listener);
  }

  Future<TData> mutate(TVariables variables) {
    _removeMutation?.call();
    final mutation = client.mutationCache.build(client, options);
    _removeMutation = mutation.subscribe(_update);
    return mutation.execute(variables);
  }

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

  void dispose() {
    _removeMutation?.call();
    _removeMutation = null;
    _listeners.clear();
  }
}
