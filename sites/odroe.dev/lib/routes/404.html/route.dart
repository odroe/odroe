import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

final route =
    AppRoute<NoParams, NoSearch, NoData>(
      metadata: const RouteMetadata(
        title: 'Page not found · Odroe',
        description: 'The requested Odroe page does not exist.',
      ),
    ).document(
      (_) => RouteDocument(
        meta: const <DocumentMeta>[
          DocumentMeta.name('robots', 'noindex,nofollow'),
        ],
        body: HtmlElement(
          'section',
          attributes: const <String, String?>{'class': 'not-found'},
          children: const <HtmlNode>[
            HtmlElement(
              'p',
              attributes: <String, String?>{'class': 'eyebrow'},
              children: <HtmlNode>[HtmlText('404')],
            ),
            HtmlElement(
              'h1',
              children: <HtmlNode>[HtmlText('This route ends here.')],
            ),
            HtmlElement(
              'p',
              children: <HtmlNode>[
                HtmlText(
                  'Return home or continue with the getting started guide.',
                ),
              ],
            ),
            HtmlElement(
              'div',
              attributes: <String, String?>{'class': 'hero-actions'},
              children: <HtmlNode>[
                HtmlElement(
                  'a',
                  attributes: <String, String?>{
                    'class': 'button primary',
                    'href': '/',
                  },
                  children: <HtmlNode>[HtmlText('Back home')],
                ),
                HtmlElement(
                  'a',
                  attributes: <String, String?>{
                    'class': 'button',
                    'href': '/docs/getting-started',
                  },
                  children: <HtmlNode>[HtmlText('Read the guide')],
                ),
              ],
            ),
          ],
        ),
      ),
    );
