import 'package:odroe/document.dart';

import 'home.dart';
import 'html.dart';

const _github = 'https://github.com/odroe/odroe';

RouteDocument buildSiteDocument({required bool home}) => RouteDocument(
  language: 'en',
  canonical: home ? 'https://odroe.dev/' : null,
  links: const <DocumentLink>[
    DocumentLink(rel: 'stylesheet', href: '/site.css'),
    DocumentLink(rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml'),
  ],
  meta: const <DocumentMeta>[
    DocumentMeta.name('theme-color', '#ffffff'),
    DocumentMeta.property('og:site_name', 'Odroe'),
    DocumentMeta.property('og:type', 'website'),
    DocumentMeta.property('og:image', 'https://odroe.dev/social-card.svg'),
    DocumentMeta.name('twitter:card', 'summary_large_image'),
  ],
  jsonLd: home
      ? const <Object?>[
          <String, Object?>{
            '@context': 'https://schema.org',
            '@type': 'SoftwareApplication',
            'name': 'Odroe',
            'applicationCategory': 'DeveloperApplication',
            'operatingSystem': 'Cross-platform',
            'url': 'https://odroe.dev',
            'codeRepository': _github,
          },
        ]
      : const <Object?>[],
  bodyAttributes: const <String, String?>{'class': 'site-body'},
  body: element(
    'div',
    attributes: const <String, String?>{'class': 'site'},
    children: <HtmlNode>[
      element(
        'a',
        attributes: const <String, String?>{
          'class': 'skip-link',
          'href': '#main-content',
        },
        children: <HtmlNode>[text('Skip to content')],
      ),
      _header(),
      element(
        'main',
        attributes: const <String, String?>{'id': 'main-content'},
        children: <HtmlNode>[home ? buildHome() : const HtmlOutlet()],
      ),
      _footer(),
    ],
  ),
);

HtmlElement _header() => element(
  'header',
  attributes: const <String, String?>{'class': 'site-header'},
  children: <HtmlNode>[
    element(
      'a',
      attributes: const <String, String?>{
        'class': 'wordmark',
        'href': '/',
        'aria-label': 'Odroe home',
      },
      children: <HtmlNode>[text('Odroe')],
    ),
    element(
      'nav',
      attributes: const <String, String?>{
        'class': 'site-nav',
        'aria-label': 'Primary',
      },
      children: <HtmlNode>[
        _navLink('Docs', '/docs'),
        _navLink('Database', '/docs/data/database'),
        _navLink('Deploy', '/docs/deploy'),
        _navLink('GitHub', _github, external: true),
      ],
    ),
  ],
);

HtmlElement _navLink(String label, String href, {bool external = false}) =>
    element(
      'a',
      attributes: <String, String?>{
        'href': href,
        if (external) 'rel': 'noreferrer',
      },
      children: <HtmlNode>[text(label)],
    );

HtmlElement _footer() => element(
  'footer',
  attributes: const <String, String?>{'class': 'site-footer'},
  children: <HtmlNode>[
    element(
      'div',
      attributes: const <String, String?>{'class': 'footer-main'},
      children: <HtmlNode>[
        element(
          'div',
          children: <HtmlNode>[
            element(
              'p',
              attributes: const <String, String?>{'class': 'footer-title'},
              children: <HtmlNode>[text('Odroe')],
            ),
            element(
              'p',
              attributes: const <String, String?>{'class': 'footer-note'},
              children: <HtmlNode>[text('Open source, built in public.')],
            ),
          ],
        ),
        element(
          'nav',
          attributes: const <String, String?>{
            'class': 'footer-nav',
            'aria-label': 'Footer',
          },
          children: <HtmlNode>[
            _navLink('Documentation', '/docs'),
            _navLink('Source', _github, external: true),
            _navLink('Issues', '$_github/issues', external: true),
          ],
        ),
      ],
    ),
    element(
      'p',
      attributes: const <String, String?>{'class': 'footer-legal'},
      children: <HtmlNode>[
        text('Dart and Flutter are trademarks of Google LLC.'),
      ],
    ),
  ],
);
