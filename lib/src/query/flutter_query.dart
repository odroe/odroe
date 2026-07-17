// ignore_for_file: public_member_api_docs

import 'package:flutter/widgets.dart';

import 'client.dart';
import 'infinite.dart';
import 'managers.dart';
import 'mutation.dart';
import 'observer.dart';
import 'options.dart';

/// Installs one QueryClient for a Flutter application subtree.
final class QueryClientProvider extends StatefulWidget {
  const QueryClientProvider({
    required this.client,
    required this.child,
    super.key,
  });

  final QueryClient client;
  final Widget child;

  static QueryClient of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_QueryClientInherited>();
    if (inherited == null) {
      throw FlutterError(
        'No QueryClientProvider found. Add one above this widget or pass an '
        'explicit QueryClient.',
      );
    }
    return inherited.client;
  }

  @override
  State<QueryClientProvider> createState() => _QueryClientProviderState();
}

final class _QueryClientProviderState extends State<QueryClientProvider>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    widget.client.mount();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(QueryClientProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.client, widget.client)) return;
    oldWidget.client.unmount();
    widget.client.mount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.client.focusManager.isFocused = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) =>
      _QueryClientInherited(client: widget.client, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.unmount();
    super.dispose();
  }
}

final class _QueryClientInherited extends InheritedWidget {
  const _QueryClientInherited({required this.client, required super.child});

  final QueryClient client;

  @override
  bool updateShouldNotify(_QueryClientInherited oldWidget) =>
      !identical(client, oldWidget.client);
}

typedef QueryWidgetBuilder<T> =
    Widget Function(BuildContext context, QueryResult<T> result);

/// Rebuilds from one reusable [QueryOptions] definition.
final class QueryBuilder<T> extends StatefulWidget {
  const QueryBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  final QueryOptions<T> options;
  final QueryWidgetBuilder<T> builder;
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

typedef QuerySelectionBuilder<S> =
    Widget Function(BuildContext context, S selection);

/// Rebuilds only when a selected slice changes.
final class QuerySelector<T, S> extends StatefulWidget {
  const QuerySelector({
    required this.options,
    required this.select,
    required this.builder,
    this.equals,
    this.client,
    super.key,
  });

  final QueryOptions<T> options;
  final S Function(QueryResult<T> result) select;
  final bool Function(S previous, S next)? equals;
  final QuerySelectionBuilder<S> builder;
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

typedef MutationWidgetBuilder<TData, TVariables, TOptimistic> =
    Widget Function(
      BuildContext context,
      MutationState<TData, TVariables, TOptimistic> state,
      Future<TData> Function(TVariables variables) mutate,
      VoidCallback reset,
    );

/// Owns a MutationObserver for one Flutter widget lifecycle.
final class MutationBuilder<TData, TVariables, TOptimistic>
    extends StatefulWidget {
  const MutationBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  final MutationOptions<TData, TVariables, TOptimistic> options;
  final MutationWidgetBuilder<TData, TVariables, TOptimistic> builder;
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

  void _connect(QueryClient client) {
    if (identical(client, _client) && _observer != null) return;
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

typedef InfiniteQueryWidgetBuilder<TPage, TPageParam> =
    Widget Function(
      BuildContext context,
      InfiniteQueryResult<TPage, TPageParam> result,
      Future<InfiniteQueryResult<TPage, TPageParam>> Function() fetchNextPage,
      Future<InfiniteQueryResult<TPage, TPageParam>> Function()
      fetchPreviousPage,
    );

/// Flutter binding for the ordinary Query runtime's infinite behavior.
final class InfiniteQueryBuilder<TPage, TPageParam> extends StatefulWidget {
  const InfiniteQueryBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  final InfiniteQueryOptions<TPage, TPageParam> options;
  final InfiniteQueryWidgetBuilder<TPage, TPageParam> builder;
  final QueryClient? client;

  @override
  State<InfiniteQueryBuilder<TPage, TPageParam>> createState() =>
      _InfiniteQueryBuilderState<TPage, TPageParam>();
}

final class _InfiniteQueryBuilderState<TPage, TPageParam>
    extends State<InfiniteQueryBuilder<TPage, TPageParam>> {
  QueryClient? _client;
  InfiniteQueryObserver<TPage, TPageParam>? _observer;
  QueryDispose? _remove;
  late InfiniteQueryResult<TPage, TPageParam> _result;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = widget.client ?? QueryClientProvider.of(context);
    if (identical(client, _client) && _observer != null) return;
    _remove?.call();
    _observer?.dispose();
    _client = client;
    _observer = InfiniteQueryObserver<TPage, TPageParam>(
      client,
      widget.options,
    );
    _result = _observer!.current;
    _remove = _observer!.subscribe((result) {
      if (!mounted) {
        _result = result;
      } else {
        setState(() => _result = result);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _result,
    _observer!.fetchNextPage,
    _observer!.fetchPreviousPage,
  );

  @override
  void dispose() {
    _remove?.call();
    _observer?.dispose();
    super.dispose();
  }
}
