import 'package:odroe/router.dart';

typedef Params = ({List<String> slug});

final route = AppRoute<Params, NoSearch, NoData>(
  metadata: const RouteMetadata(title: 'Documentation'),
  params: const PathParams<Params>.schema(),
);
