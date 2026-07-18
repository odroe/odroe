import 'package:odroe/router_core.dart';

final route = AppRoute<NoParams, NoSearch, NoData>(
  document: (_) => const RouteDocument(
    language: 'en',
    title: 'Odroe Router',
    description: 'Typed full-stack routing for Flutter applications.',
    body: HtmlElement(
      'main',
      children: <HtmlNode>[
        HtmlElement('h1', children: <HtmlNode>[HtmlText('Odroe Router')]),
        HtmlElement(
          'p',
          children: <HtmlNode>[
            HtmlText('Semantic HTML first, Flutter when the app uses it.'),
          ],
        ),
        HtmlElement(
          'nav',
          children: <HtmlNode>[
            HtmlElement(
              'a',
              attributes: <String, String?>{'href': '/posts/42'},
              children: <HtmlNode>[HtmlText('Post 42')],
            ),
            HtmlElement(
              'a',
              attributes: <String, String?>{'href': '/pricing'},
              children: <HtmlNode>[HtmlText('Pricing')],
            ),
            HtmlElement(
              'a',
              attributes: <String, String?>{'href': '/about'},
              children: <HtmlNode>[HtmlText('About')],
            ),
          ],
        ),
        HtmlOutlet(),
      ],
    ),
  ),
);
