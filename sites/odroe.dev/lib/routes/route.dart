import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

import '../site/layout.dart';

final route = AppRoute<NoParams, NoSearch, NoData>(
  metadata: const RouteMetadata(title: siteTitle, description: siteDescription),
).document((context) => buildSiteDocument(home: context.location.path == '/'));
