import 'package:odroe/route.dart';

final route = AppRoute<NoParams, NoSearch, NoData>(
  document: (_) => const RouteDocument(
    title: 'About Odroe',
    description: 'A pure semantic HTML route inside a Flutter application.',
    canonical: '/about',
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
