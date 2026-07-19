import '../document/document.dart';
import '../document/node.dart';
import '../document/renderer.dart';
import '../server/http.dart';

/// Builds the default semantic error document used by the runtime.
ServerResponse renderFailureDocument({
  required int status,
  required String title,
  required String message,
  String? details,
}) {
  final document = resolveDocument(<RouteDocument>[
    RouteDocument(
      title: title,
      meta: const <DocumentMeta>[
        DocumentMeta.name('robots', 'noindex, nofollow'),
      ],
      body: HtmlElement(
        'main',
        children: <HtmlNode>[
          HtmlElement('h1', children: <HtmlNode>[HtmlText(title)]),
          HtmlElement('p', children: <HtmlNode>[HtmlText(message)]),
          if (details != null)
            HtmlElement('pre', children: <HtmlNode>[HtmlText(details)]),
        ],
      ),
    ),
  ]);
  return ServerResponse.html(
    '${renderDocumentStart(document)}</body></html>',
    status: status,
  );
}
