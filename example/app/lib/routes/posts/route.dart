import 'package:odroe/router.dart';

typedef Search = ({String sort});

final route = AppRoute<NoParams, Search, NoData>(
  metadata: const RouteMetadata(title: 'Posts'),
  search: const SearchParams<Search>.schema(defaults: (sort: 'newest')),
);
