import 'dart:async';

import 'client.dart';
import 'key.dart';
import 'managers.dart';
import 'observer.dart';
import 'options.dart';

/// Direction of one infinite-query page fetch.
enum InfiniteDirection {
  /// Fetch a page after the current last page.
  forward,

  /// Fetch a page before the current first page.
  backward,
}

/// Page data and the exact parameters that produced each page.
final class InfiniteData<TPage, TPageParam> {
  /// Creates page data with one parameter for every page.
  InfiniteData({
    required Iterable<TPage> pages,
    required Iterable<TPageParam> pageParams,
  }) : pages = List<TPage>.unmodifiable(pages),
       pageParams = List<TPageParam>.unmodifiable(pageParams) {
    if (this.pages.length != this.pageParams.length) {
      throw ArgumentError('pages and pageParams must have equal length.');
    }
  }

  /// Pages in display order.
  final List<TPage> pages;

  /// Parameters that produced [pages], in the same order.
  final List<TPageParam> pageParams;
}

/// Input supplied while fetching one page.
final class InfinitePageContext<TPageParam> {
  /// Creates input for one page fetch.
  const InfinitePageContext({
    required this.query,
    required this.pageParam,
    required this.direction,
  });

  /// The underlying query context.
  final QueryContext query;

  /// The parameter for the page being fetched.
  final TPageParam pageParam;

  /// Where the page will be added.
  final InfiniteDirection direction;
}

/// Fetches one page of an infinite query.
typedef InfinitePageFunction<TPage, TPageParam> =
    FutureOr<TPage> Function(InfinitePageContext<TPageParam> context);

/// Selects the parameter for the page after the current last page.
typedef InfiniteNextPage<TPage, TPageParam> =
    TPageParam? Function(
      TPage lastPage,
      List<TPage> pages,
      TPageParam lastPageParam,
      List<TPageParam> pageParams,
    );

/// Selects the parameter for the page before the current first page.
typedef InfinitePreviousPage<TPage, TPageParam> =
    TPageParam? Function(
      TPage firstPage,
      List<TPage> pages,
      TPageParam firstPageParam,
      List<TPageParam> pageParams,
    );

/// A typed infinite query definition backed by the ordinary Query runtime.
final class InfiniteQueryOptions<TPage, TPageParam> {
  /// Creates an infinite query definition.
  InfiniteQueryOptions({
    required this.key,
    required this.query,
    required this.initialPageParam,
    required this.getNextPageParam,
    this.getPreviousPageParam,
    this.maxPages,
    this.policy = const QueryPolicy(),
    this.meta = const <String, Object?>{},
  }) {
    if (maxPages != null && maxPages! <= 0) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be positive.');
    }
  }

  /// The cache key shared by all pages.
  final QueryKey key;

  /// Fetches one page.
  final InfinitePageFunction<TPage, TPageParam> query;

  /// The parameter used for the first page.
  final TPageParam initialPageParam;

  /// Selects the next page parameter.
  final InfiniteNextPage<TPage, TPageParam> getNextPageParam;

  /// Selects the previous page parameter, when backward paging is supported.
  final InfinitePreviousPage<TPage, TPageParam>? getPreviousPageParam;

  /// Maximum retained pages, or `null` for no limit.
  final int? maxPages;

  /// Query runtime policy for page fetching.
  final QueryPolicy policy;

  /// User metadata passed to each page fetch.
  final Map<String, Object?> meta;

  /// The ordinary query definition used to store this infinite query.
  late final QueryOptions<InfiniteData<TPage, TPageParam>> queryOptions =
      QueryOptions<InfiniteData<TPage, TPageParam>>(
        key: key,
        policy: policy,
        meta: meta,
        query: _fetch,
        merge: (_, next) => next,
      );

  Future<InfiniteData<TPage, TPageParam>> _fetch(QueryContext context) async {
    final old = context.client.getQueryData<InfiniteData<TPage, TPageParam>>(
      key,
    );
    final direction = switch (context.fetchMeta?.kind) {
      'infinite.forward' => InfiniteDirection.forward,
      'infinite.backward' => InfiniteDirection.backward,
      _ => null,
    };

    if (direction != null && old != null && old.pages.isNotEmpty) {
      final parameter = direction == InfiniteDirection.forward
          ? getNextPageParam(
              old.pages.last,
              old.pages,
              old.pageParams.last,
              old.pageParams,
            )
          : getPreviousPageParam?.call(
              old.pages.first,
              old.pages,
              old.pageParams.first,
              old.pageParams,
            );
      if (parameter == null) return old;
      final page = await query(
        InfinitePageContext<TPageParam>(
          query: context,
          pageParam: parameter,
          direction: direction,
        ),
      );
      final pages = <TPage>[...old.pages];
      final params = <TPageParam>[...old.pageParams];
      if (direction == InfiniteDirection.forward) {
        pages.add(page);
        params.add(parameter);
        if (maxPages != null && pages.length > maxPages!) {
          pages.removeAt(0);
          params.removeAt(0);
        }
      } else {
        pages.insert(0, page);
        params.insert(0, parameter);
        if (maxPages != null && pages.length > maxPages!) {
          pages.removeLast();
          params.removeLast();
        }
      }
      return InfiniteData<TPage, TPageParam>(pages: pages, pageParams: params);
    }

    final targetPages = old?.pages.length ?? 1;
    final pages = <TPage>[];
    final params = <TPageParam>[];
    var parameter = old?.pageParams.first ?? initialPageParam;
    for (var index = 0; index < targetPages; index++) {
      context.cancelToken.throwIfCancelled();
      final page = await query(
        InfinitePageContext<TPageParam>(
          query: context,
          pageParam: parameter,
          direction: InfiniteDirection.forward,
        ),
      );
      pages.add(page);
      params.add(parameter);
      if (index + 1 >= targetPages) break;
      final next = getNextPageParam(page, pages, parameter, params);
      if (next == null) break;
      parameter = next;
    }
    return InfiniteData<TPage, TPageParam>(pages: pages, pageParams: params);
  }

  /// Whether [data] provides another forward page parameter.
  bool hasNextPage(InfiniteData<TPage, TPageParam>? data) =>
      data != null &&
      data.pages.isNotEmpty &&
      getNextPageParam(
            data.pages.last,
            data.pages,
            data.pageParams.last,
            data.pageParams,
          ) !=
          null;

  /// Whether [data] provides another backward page parameter.
  bool hasPreviousPage(InfiniteData<TPage, TPageParam>? data) =>
      data != null &&
      data.pages.isNotEmpty &&
      getPreviousPageParam?.call(
            data.pages.first,
            data.pages,
            data.pageParams.first,
            data.pageParams,
          ) !=
          null;
}

/// UI-facing result with pagination-specific transport flags.
final class InfiniteQueryResult<TPage, TPageParam> {
  /// Creates an infinite query result projection.
  const InfiniteQueryResult({
    required this.query,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.isFetchingNextPage,
    required this.isFetchingPreviousPage,
  });

  /// The underlying ordinary query result.
  final QueryResult<InfiniteData<TPage, TPageParam>> query;

  /// Whether a forward page can be fetched.
  final bool hasNextPage;

  /// Whether a backward page can be fetched.
  final bool hasPreviousPage;

  /// Whether a forward page fetch is running.
  final bool isFetchingNextPage;

  /// Whether a backward page fetch is running.
  final bool isFetchingPreviousPage;
}

/// Observer for infinite-query controls; storage remains a normal Query entry.
final class InfiniteQueryObserver<TPage, TPageParam> {
  /// Creates an observer for [options] on [client].
  InfiniteQueryObserver(this.client, this.options)
    : _observer = QueryObserver<InfiniteData<TPage, TPageParam>>(
        client,
        options.queryOptions,
      );

  /// The client that owns the query.
  final QueryClient client;

  /// The infinite query definition.
  final InfiniteQueryOptions<TPage, TPageParam> options;
  final QueryObserver<InfiniteData<TPage, TPageParam>> _observer;

  /// The current result projection.
  InfiniteQueryResult<TPage, TPageParam> get current =>
      _result(_observer.current);

  /// Subscribes to infinite query results.
  QueryDispose subscribe(
    void Function(InfiniteQueryResult<TPage, TPageParam> result) listener,
  ) => _observer.subscribe((result) => listener(_result(result)));

  /// Fetches and appends the next page when available.
  Future<InfiniteQueryResult<TPage, TPageParam>> fetchNextPage({
    bool cancelRefetch = true,
  }) async {
    try {
      await client
          .query(options.queryOptions)
          .fetch(
            cancelRefetch: cancelRefetch,
            meta: const QueryFetchMeta(kind: 'infinite.forward'),
          );
    } on Object {
      // Result exposes the failure without losing prior pages.
    }
    return current;
  }

  /// Fetches and prepends the previous page when available.
  Future<InfiniteQueryResult<TPage, TPageParam>> fetchPreviousPage({
    bool cancelRefetch = true,
  }) async {
    try {
      await client
          .query(options.queryOptions)
          .fetch(
            cancelRefetch: cancelRefetch,
            meta: const QueryFetchMeta(kind: 'infinite.backward'),
          );
    } on Object {
      // Result exposes the failure without losing prior pages.
    }
    return current;
  }

  InfiniteQueryResult<TPage, TPageParam> _result(
    QueryResult<InfiniteData<TPage, TPageParam>> result,
  ) {
    final kind = result.state.fetchMeta is QueryFetchMeta
        ? (result.state.fetchMeta! as QueryFetchMeta).kind
        : null;
    return InfiniteQueryResult<TPage, TPageParam>(
      query: result,
      hasNextPage: options.hasNextPage(result.data),
      hasPreviousPage: options.hasPreviousPage(result.data),
      isFetchingNextPage: result.isFetching && kind == 'infinite.forward',
      isFetchingPreviousPage: result.isFetching && kind == 'infinite.backward',
    );
  }

  /// Releases resources held by the underlying observer.
  void dispose() => _observer.dispose();
}
