import 'package:odroe/router.dart';

typedef Params = ({String slug});

final route = AppRoute<Params, NoSearch, NoData>(
  params: const PathParams<Params>.schema(),
);
