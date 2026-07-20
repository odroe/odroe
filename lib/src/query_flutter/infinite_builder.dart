import 'package:flutter/widgets.dart';

import '../query/client.dart';
import '../query/infinite.dart';
import '../query/managers.dart';
import 'provider.dart';

/// Builds a widget from an infinite query and its paging actions.
typedef InfiniteQueryWidgetBuilder<TPage, TPageParam> =
    Widget Function(
      BuildContext context,
      InfiniteQueryResult<TPage, TPageParam> result,
      Future<InfiniteQueryResult<TPage, TPageParam>> Function() fetchNextPage,
      Future<InfiniteQueryResult<TPage, TPageParam>> Function()
      fetchPreviousPage,
    );

/// Observes an infinite query for one Flutter widget lifecycle.
final class InfiniteQueryBuilder<TPage, TPageParam> extends StatefulWidget {
  /// Creates an infinite query-backed widget.
  const InfiniteQueryBuilder({
    required this.options,
    required this.builder,
    this.client,
    super.key,
  });

  /// Defines the infinite query observed by this widget.
  final InfiniteQueryOptions<TPage, TPageParam> options;

  /// Builds from the current result and paging actions.
  final InfiniteQueryWidgetBuilder<TPage, TPageParam> builder;

  /// An explicit client, or `null` to use [QueryClientProvider].
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
    _connect(widget.client ?? QueryClientProvider.of(context));
  }

  @override
  void didUpdateWidget(InfiniteQueryBuilder<TPage, TPageParam> oldWidget) {
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
