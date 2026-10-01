import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

import '../../docs.dart';
import '../../site/docs.dart';

final route = AppRoute<NoParams, NoSearch, DocsData>().document(
  (context) => context.location.path == '/docs'
      ? buildDocsDocument(context.data)
      : const RouteDocument(),
);
