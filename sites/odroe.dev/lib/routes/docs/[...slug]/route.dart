import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

import '../../../docs.dart';
import '../../../site/docs.dart';

typedef Params = ({List<String> slug});

final route = AppRoute<Params, NoSearch, DocsData>(
  params: const PathParams<Params>.schema(),
).document((context) => buildDocsDocument(context.data));
