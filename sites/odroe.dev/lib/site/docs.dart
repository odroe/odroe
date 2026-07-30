import 'package:odroe/document.dart';
import 'package:odroe/mdc.dart';
import 'package:odroe/press.dart';

import '../docs.dart';
import 'html.dart';

RouteDocument buildDocsDocument(DocsData data) {
  final canonical = Uri.parse(
    'https://odroe.dev',
  ).resolveUri(data.page.location).toString();
  final title = '${data.page.title} · Odroe';
  return RouteDocument(
    language: data.page.language,
    title: title,
    description: data.page.description,
    canonical: canonical,
    meta: <DocumentMeta>[
      const DocumentMeta.property('og:type', 'article'),
      DocumentMeta.property('og:title', title),
      DocumentMeta.property('og:description', data.page.description),
      DocumentMeta.property('og:url', canonical),
    ],
    bodyAttributes: const <String, String?>{'class': 'site-body docs-body'},
    body: element(
      'div',
      attributes: const <String, String?>{'class': 'docs-layout'},
      children: <HtmlNode>[
        _navigation(data, 'docs-sidebar'),
        _mobileNavigation(data),
        element(
          'article',
          attributes: const <String, String?>{'class': 'docs-article'},
          children: <HtmlNode>[
            element(
              'p',
              attributes: const <String, String?>{'class': 'docs-breadcrumb'},
              children: <HtmlNode>[
                element(
                  'a',
                  attributes: const <String, String?>{'href': '/docs'},
                  children: <HtmlNode>[text('Docs')],
                ),
                text(' / ${_section(data.page)}'),
              ],
            ),
            MdcHtmlRenderer().render(data.page.content),
          ],
        ),
        _outline(data.page),
      ],
    ),
  );
}

HtmlElement _mobileNavigation(DocsData data) => element(
  'details',
  attributes: const <String, String?>{'class': 'docs-mobile-nav'},
  children: <HtmlNode>[
    element('summary', children: <HtmlNode>[text('Documentation menu')]),
    _navigation(data, 'docs-mobile-links'),
  ],
);

HtmlElement _navigation(DocsData data, String className) {
  final groups = <String, List<PressPage>>{};
  for (final page in data.navigation) {
    (groups[_section(page)] ??= <PressPage>[]).add(page);
  }
  return element(
    'nav',
    attributes: <String, String?>{
      'class': className,
      'aria-label': 'Documentation',
    },
    children: <HtmlNode>[
      element(
        'p',
        attributes: const <String, String?>{'class': 'docs-nav-title'},
        children: <HtmlNode>[text('Documentation')],
      ),
      for (final entry in groups.entries)
        element(
          'section',
          attributes: const <String, String?>{'class': 'docs-nav-group'},
          children: <HtmlNode>[
            element('h2', children: <HtmlNode>[text(entry.key)]),
            element(
              'ul',
              children: <HtmlNode>[
                for (final page in entry.value)
                  element(
                    'li',
                    children: <HtmlNode>[
                      element(
                        'a',
                        attributes: <String, String?>{
                          'href': page.location.toString(),
                          if (page.location == data.page.location)
                            'aria-current': 'page',
                        },
                        children: <HtmlNode>[text(page.title)],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
    ],
  );
}

HtmlElement _outline(PressPage page) => element(
  'aside',
  attributes: const <String, String?>{
    'class': 'docs-outline',
    'aria-label': 'On this page',
  },
  children: <HtmlNode>[
    element('h2', children: <HtmlNode>[text('On this page')]),
    element(
      'ol',
      children: <HtmlNode>[
        for (final entry in _outlineEntries(page.outline))
          element(
            'li',
            attributes: <String, String?>{'class': 'depth-${entry.level}'},
            children: <HtmlNode>[
              element(
                'a',
                attributes: <String, String?>{'href': '#${entry.id}'},
                children: <HtmlNode>[text(entry.title)],
              ),
            ],
          ),
      ],
    ),
  ],
);

String _section(PressPage page) {
  if (page.slug.isEmpty || page.slug.first == 'getting-started') {
    return 'Introduction';
  }
  return switch (page.slug.first) {
    'core' => 'Core',
    'web' => 'Web',
    'data' => 'Data',
    'deploy' => 'Deployment',
    'server' => 'Core',
    _ => 'Guides',
  };
}

Iterable<MdcOutlineEntry> _outlineEntries(
  Iterable<MdcOutlineEntry> entries,
) sync* {
  for (final entry in entries) {
    if (entry.level <= 3) yield entry;
    yield* _outlineEntries(entry.children);
  }
}
