// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'client.dart';
import 'key.dart';
import 'managers.dart';
import 'observer.dart';
import 'options.dart';

enum InfiniteDirection { forward, backward }

/// Page data and the exact parameters that produced each page.
final class InfiniteData<TPage, TPageParam> {
  InfiniteData({
    required Iterable<TPage> pages,
    required Iterable<TPageParam> pageParams,
  }) : pages = List<TPage>.unmodifiable(pages),
       pageParams = List<TPageParam>.unmodifiable(pageParams) {
    if (this.pages.length != this.pageParams.length) {
      throw ArgumentError('pages and pageParams must have equal length.');
    }
  }

  final List<TPage> pages;
  final List<TPageParam> pageParams;
}

/// Input supplied while fetching one page.
final class InfinitePageContext<TPageParam> {
  const InfinitePageContext({
    required this.query,
    required this.pageParam,
    required this.direction,
  });

  final QueryContext query;
  final TPageParam pageParam;
  final InfiniteDirection direction;
}

typedef InfinitePageFunction<TPage, TPageParam> =
    FutureOr<TPage> Function(InfinitePageContext<TPageParam> context);
typedef InfiniteNextPage<TPage, TPageParam> =
    TPageParam? Function(
      TPage lastPage,
      List<TPage> pages,
      TPageParam lastPageParam,
      List<TPageParam> pageParams,
    );
typedef InfinitePreviousPage<TPage, TPageParam> =
    TPageParam? Function(
      TPage firstPage,
      List<TPage> pages,
      TPageParam firstPageParam,
      List<TPageParam> pageParams,
    );

/// A typed infinite query definition backed by the ordinary Query runtime.
final class InfiniteQueryOptions<TPage, TPageParam> {
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

  final QueryKey key;
  final InfinitePageFunction<TPage, TPageParam> query;
  final TPageParam initialPageParam;
  final InfiniteNextPage<TPage, TPageParam> getNextPageParam;
  final InfinitePreviousPage<TPage, TPageParam>? getPreviousPageParam;
  final int? maxPages;
  final QueryPolicy policy;
  final Map<String, Object?> meta;

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
  const InfiniteQueryResult({
    required this.query,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.isFetchingNextPage,
    required this.isFetchingPreviousPage,
  });

  final QueryResult<InfiniteData<TPage, TPageParam>> query;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final bool isFetchingNextPage;
  final bool isFetchingPreviousPage;
}

/// Observer for infinite-query controls; storage remains a normal Query entry.
final class InfiniteQueryObserver<TPage, TPageParam> {
  InfiniteQueryObserver(this.client, this.options)
    : _observer = QueryObserver<InfiniteData<TPage, TPageParam>>(
        client,
        options.queryOptions,
      );

  final QueryClient client;
  final InfiniteQueryOptions<TPage, TPageParam> options;
  final QueryObserver<InfiniteData<TPage, TPageParam>> _observer;

  InfiniteQueryResult<TPage, TPageParam> get current =>
      _result(_observer.current);

  QueryDispose subscribe(
    void Function(InfiniteQueryResult<TPage, TPageParam> result) listener,
  ) => _observer.subscribe((result) => listener(_result(result)));

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

  void dispose() => _observer.dispose();
}
