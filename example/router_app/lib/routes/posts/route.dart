import 'package:odroe/router_core.dart';

typedef Search = ({String sort});

final route = AppRoute<NoParams, Search, NoData>(
  search: const SearchParams<Search>.schema(defaults: (sort: 'newest')),
);
