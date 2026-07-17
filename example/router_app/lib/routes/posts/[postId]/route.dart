import 'package:odroe/router_core.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview, List<String> tags});

final route = AppRoute<Params, Search, NoData>(
  params: const PathParams<Params>.schema(),
  search: const SearchParams<Search>.schema(
    defaults: (preview: false, tags: <String>[]),
  ),
);
