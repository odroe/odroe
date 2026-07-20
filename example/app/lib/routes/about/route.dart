import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

final route =
    AppRoute<NoParams, NoSearch, NoData>(
      metadata: const RouteMetadata(
        title: 'About Odroe',
        description: 'A pure semantic HTML route inside a Flutter application.',
        canonical: '/about',
      ),
    ).document(
      (_) => const RouteDocument(
        body: HtmlElement(
          'article',
          children: <HtmlNode>[
            HtmlElement('h1', children: <HtmlNode>[HtmlText('About Odroe')]),
            HtmlElement(
              'p',
              children: <HtmlNode>[
                HtmlText('This route does not load the Flutter application.'),
              ],
            ),
          ],
        ),
      ),
    );
