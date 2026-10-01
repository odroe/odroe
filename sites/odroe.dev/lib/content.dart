import 'package:odroe/press_io.dart';
import 'package:odroe/server.dart';

import 'docs.dart';

final docs = PressDirectory('content/docs', mount: '/docs');

Future<DocsData> loadDocs(Iterable<String> slug) async {
  final press = await docs.snapshot();
  final page = press.page(slug);
  if (page == null) throw const NotFound('Documentation page not found.');
  return DocsData(page: page, navigation: press.pages);
}
