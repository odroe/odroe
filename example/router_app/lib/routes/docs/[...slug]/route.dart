import 'package:odroe/router_core.dart';

typedef Params = ({List<String> slug});

final route = AppRoute<Params, NoSearch, NoData>(
  params: const PathParams<Params>.schema(),
);
