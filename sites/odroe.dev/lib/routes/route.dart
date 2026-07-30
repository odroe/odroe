import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

import '../site/layout.dart';

final route = AppRoute<NoParams, NoSearch, NoData>(
  metadata: const RouteMetadata(
    title: 'Odroe · One Dart package. Every layer.',
    description:
        'Build Flutter apps, semantic web experiences, and typed servers '
        'with one explicit Dart package.',
  ),
).document((context) => buildSiteDocument(home: context.location.path == '/'));
