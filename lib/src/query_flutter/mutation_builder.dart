import 'package:flutter/widgets.dart';

import '../query/client.dart';
import '../query/managers.dart';
import '../query/mutation.dart';
import 'provider.dart';

/// Builds a widget from a mutation state and its actions.
typedef MutationWidgetBuilder<TData, TVariables, TOptimistic> =
    Widget Function(
      BuildContext context,
      MutationState<TData, TVariables, TOptimistic> state,
      Future<TData> Function(TVariables variables) mutate,
      VoidCallback reset,
    );

/// Owns a mutation observer for one Flutter widget lifecycle.
final class MutationBuilder<TData, TVariables, TOptimistic>
    extends StatefulWidget {
  /// Creates a mutation-backed widget.
  const MutationBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  /// Defines the mutation observed by this widget.
  final MutationOptions<TData, TVariables, TOptimistic> options;

  /// Builds from the current mutation state and actions.
  final MutationWidgetBuilder<TData, TVariables, TOptimistic> builder;

  /// An explicit client, or `null` to use [QueryClientProvider].
  final QueryClient? client;

  @override
  State<MutationBuilder<TData, TVariables, TOptimistic>> createState() =>
      _MutationBuilderState<TData, TVariables, TOptimistic>();
}

final class _MutationBuilderState<TData, TVariables, TOptimistic>
    extends State<MutationBuilder<TData, TVariables, TOptimistic>> {
  QueryClient? _client;
  MutationObserver<TData, TVariables, TOptimistic>? _observer;
  QueryDispose? _remove;
  late MutationState<TData, TVariables, TOptimistic> _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connect(widget.client ?? QueryClientProvider.of(context));
  }

  @override
  void didUpdateWidget(
    MutationBuilder<TData, TVariables, TOptimistic> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    _connect(
      widget.client ?? QueryClientProvider.of(context),
      force: !identical(oldWidget.options, widget.options),
    );
  }

  void _connect(QueryClient client, {bool force = false}) {
    if (!force && identical(client, _client) && _observer != null) return;
    _remove?.call();
    _observer?.dispose();
    _client = client;
    _observer = client.observeMutation(widget.options);
    _state = _observer!.current;
    _remove = _observer!.subscribe((state) {
      if (!mounted || identical(state, _state)) {
        _state = state;
      } else {
        setState(() => _state = state);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _state, _observer!.mutate, _observer!.reset);

  @override
  void dispose() {
    _remove?.call();
    _observer?.dispose();
    super.dispose();
  }
}
