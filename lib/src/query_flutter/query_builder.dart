import 'package:flutter/widgets.dart';

import '../query/client.dart';
import '../query/managers.dart';
import '../query/observer.dart';
import '../query/options.dart';
import 'provider.dart';

/// Builds a widget from the current result of one query.
typedef QueryWidgetBuilder<T> =
    Widget Function(BuildContext context, QueryResult<T> result);

/// Observes one reusable [QueryOptions] definition for a widget subtree.
final class QueryBuilder<T> extends StatefulWidget {
  /// Creates a query-backed widget.
  const QueryBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  /// The query to observe.
  final QueryOptions<T> options;

  /// Builds from the current query result.
  final QueryWidgetBuilder<T> builder;

  /// An explicit client, or `null` to use [QueryClientProvider].
  final QueryClient? client;

  @override
  State<QueryBuilder<T>> createState() => _QueryBuilderState<T>();
}

final class _QueryBuilderState<T> extends State<QueryBuilder<T>> {
  QueryClient? _client;
  QueryObserver<T>? _observer;
  QueryDispose? _remove;
  QueryResult<T>? _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connect(widget.client ?? QueryClientProvider.of(context));
  }

  @override
  void didUpdateWidget(QueryBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextClient = widget.client ?? QueryClientProvider.of(context);
    if (!identical(nextClient, _client)) {
      _connect(nextClient);
    } else if (!identical(oldWidget.options, widget.options)) {
      _observer!.setOptions(widget.options);
    }
  }

  void _connect(QueryClient client) {
    if (identical(_client, client) && _observer != null) return;
    _remove?.call();
    _observer?.dispose();
    _client = client;
    _observer = client.observe(widget.options);
    _result = _observer!.current;
    _remove = _observer!.subscribe(_update);
  }

  void _update(QueryResult<T> result) {
    if (result == _result) return;
    if (!mounted) {
      _result = result;
      return;
    }
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _result!);

  @override
  void dispose() {
    _remove?.call();
    _observer?.dispose();
    super.dispose();
  }
}

/// Builds a widget from a selected slice of a query result.
typedef QuerySelectionBuilder<S> =
    Widget Function(BuildContext context, S selection);

/// Rebuilds only when the selected query result changes.
final class QuerySelector<T, S> extends StatefulWidget {
  /// Creates a query result selector.
  const QuerySelector({
    required this.options,
    required this.select,
    required this.builder,
    this.equals,
    this.client,
    super.key,
  });

  /// The query to observe.
  final QueryOptions<T> options;

  /// Selects the value exposed to [builder].
  final S Function(QueryResult<T> result) select;

  /// Compares the previous and next selections.
  final bool Function(S previous, S next)? equals;

  /// Builds from the selected value.
  final QuerySelectionBuilder<S> builder;

  /// An explicit client, or `null` to use [QueryClientProvider].
  final QueryClient? client;

  @override
  State<QuerySelector<T, S>> createState() => _QuerySelectorState<T, S>();
}

final class _QuerySelectorState<T, S> extends State<QuerySelector<T, S>> {
  QueryClient? _client;
  QueryObserver<T>? _observer;
  QueryDispose? _remove;
  S? _selection;
  bool _hasSelection = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connect(widget.client ?? QueryClientProvider.of(context));
  }

  @override
  void didUpdateWidget(QuerySelector<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final client = widget.client ?? QueryClientProvider.of(context);
    if (!identical(client, _client)) {
      _connect(client);
    } else {
      if (!identical(oldWidget.options, widget.options)) {
        _observer!.setOptions(widget.options);
      }
      if (!identical(oldWidget.select, widget.select)) {
        _update(_observer!.current);
      }
    }
  }

  void _connect(QueryClient client) {
    if (identical(client, _client) && _observer != null) return;
    _remove?.call();
    _observer?.dispose();
    _client = client;
    _observer = client.observe(widget.options);
    _selection = widget.select(_observer!.current);
    _hasSelection = true;
    _remove = _observer!.subscribe(_update);
  }

  void _update(QueryResult<T> result) {
    final next = widget.select(result);
    final equal =
        _hasSelection &&
        (widget.equals?.call(_selection as S, next) ?? _selection == next);
    if (equal) return;
    if (!mounted) {
      _selection = next;
      _hasSelection = true;
      return;
    }
    setState(() {
      _selection = next;
      _hasSelection = true;
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _selection as S);

  @override
  void dispose() {
    _remove?.call();
    _observer?.dispose();
    super.dispose();
  }
}
