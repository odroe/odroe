import 'package:odroe/document.dart';

import 'html.dart';

const _github = 'https://github.com/odroe/odroe';

HtmlFragment buildHome() => HtmlFragment(<HtmlNode>[
  _hero(),
  _architecture(),
  _principles(),
  _output(),
  _closing(),
]);

HtmlElement _hero() => element(
  'section',
  attributes: const <String, String?>{
    'class': 'hero section',
    'aria-labelledby': 'hero-title',
  },
  children: <HtmlNode>[
    element(
      'div',
      attributes: const <String, String?>{'class': 'hero-copy'},
      children: <HtmlNode>[
        element(
          'p',
          attributes: const <String, String?>{'class': 'eyebrow'},
          children: <HtmlNode>[
            text('The product-first Dart framework · Source preview'),
          ],
        ),
        element(
          'h1',
          attributes: const <String, String?>{'id': 'hero-title'},
          children: <HtmlNode>[
            element(
              'span',
              attributes: const <String, String?>{'class': 'hero-line'},
              children: <HtmlNode>[text('One Dart package.')],
            ),
            element('br'),
            text('Every layer.'),
          ],
        ),
        element(
          'p',
          attributes: const <String, String?>{'class': 'hero-lede'},
          children: <HtmlNode>[
            text(
              'Build Flutter apps, semantic web experiences, and typed '
              'servers without stitching together a framework stack.',
            ),
          ],
        ),
        element(
          'div',
          attributes: const <String, String?>{'class': 'hero-actions'},
          children: <HtmlNode>[
            _button('Get started', '/docs/getting-started', primary: true),
            _button('View on GitHub', _github),
          ],
        ),
      ],
    ),
    element(
      'div',
      attributes: const <String, String?>{
        'class': 'hero-system',
        'aria-label': 'One application model reaches every product layer',
      },
      children: <HtmlNode>[
        _codeWindow(),
        element(
          'ol',
          attributes: const <String, String?>{'class': 'hero-layers'},
          children: <HtmlNode>[
            _heroLayer('App', 'Flutter', 'phone', green: true),
            _heroLayer('Web', 'Semantic', 'globe', green: true),
            _heroLayer('Server', 'Typed', 'server'),
            _heroLayer('Data', 'Typed SQL', 'database'),
            _heroLayer('Edge', 'Cloudflare preview', 'cloud'),
          ],
        ),
      ],
    ),
  ],
);

HtmlElement _codeWindow() => element(
  'figure',
  attributes: const <String, String?>{'class': 'code-window'},
  children: <HtmlNode>[
    element(
      'figcaption',
      children: <HtmlNode>[_icon('file'), text('main.dart')],
    ),
    element(
      'pre',
      children: <HtmlNode>[
        element(
          'code',
          children: <HtmlNode>[
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-blue'},
              children: <HtmlNode>[text('App')],
            ),
            text('(\n  modules: [\n'),
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-green'},
              children: <HtmlNode>[text('    QueryModule()')],
            ),
            text(',\n'),
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-blue'},
              children: <HtmlNode>[
                text('    RpcModule.http(baseUri: rpcBaseUri())'),
              ],
            ),
            text(',\n'),
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-green'},
              children: <HtmlNode>[text('    DocumentModule()')],
            ),
            text(',\n'),
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-blue'},
              children: <HtmlNode>[text('    RouterModule')],
            ),
            text('(routes: routeTree),\n  ],\n  builder: (app) =>\n'),
            element(
              'span',
              attributes: const <String, String?>{'class': 'code-green'},
              children: <HtmlNode>[text('    MaterialApp.router')],
            ),
            text('(\n      routerConfig: app.read(routerKey),\n    ),\n)'),
          ],
        ),
      ],
    ),
  ],
);

HtmlElement _heroLayer(
  String title,
  String subtitle,
  String icon, {
  bool green = false,
}) => element(
  'li',
  attributes: <String, String?>{
    'class': green ? 'hero-layer green' : 'hero-layer blue',
  },
  children: <HtmlNode>[
    _icon(icon),
    element(
      'span',
      children: <HtmlNode>[
        element('strong', children: <HtmlNode>[text(title)]),
        element('small', children: <HtmlNode>[text(subtitle)]),
      ],
    ),
  ],
);

HtmlElement _architecture() => element(
  'section',
  attributes: const <String, String?>{
    'class': 'architecture section',
    'aria-labelledby': 'architecture-title',
  },
  children: <HtmlNode>[
    element(
      'div',
      attributes: const <String, String?>{'class': 'section-heading centered'},
      children: <HtmlNode>[
        element(
          'p',
          attributes: const <String, String?>{'class': 'eyebrow'},
          children: <HtmlNode>[text('One application model')],
        ),
        element(
          'h2',
          attributes: const <String, String?>{'id': 'architecture-title'},
          children: <HtmlNode>[
            text('One model, from interface to infrastructure.'),
          ],
        ),
        element(
          'p',
          children: <HtmlNode>[
            text(
              'Odroe keeps routes, inputs, and results explicit at each '
              'boundary—so every runtime contract stays reviewable.',
            ),
          ],
        ),
      ],
    ),
    element(
      'ol',
      attributes: const <String, String?>{'class': 'layer-flow'},
      children: <HtmlNode>[
        _layer('App', 'Flutter UI', 'phone', green: true),
        _layer('Web', 'Semantic Web', 'globe', green: true),
        _layer('Server', 'Typed Routes & RPC', 'server'),
        _layer('Data', 'Typed Queries', 'database'),
        _layer('Edge', 'Cloudflare Preview', 'cloud'),
      ],
    ),
  ],
);

HtmlElement _layer(
  String title,
  String subtitle,
  String icon, {
  bool green = false,
}) => element(
  'li',
  attributes: <String, String?>{'class': green ? 'layer green' : 'layer blue'},
  children: <HtmlNode>[
    element(
      'span',
      attributes: const <String, String?>{'class': 'layer-icon'},
      children: <HtmlNode>[_icon(icon)],
    ),
    element(
      'span',
      attributes: const <String, String?>{'class': 'layer-label'},
      children: <HtmlNode>[
        element('strong', children: <HtmlNode>[text(title)]),
        element('small', children: <HtmlNode>[text(subtitle)]),
      ],
    ),
  ],
);

HtmlElement _principles() => element(
  'section',
  attributes: const <String, String?>{
    'class': 'principles section',
    'aria-labelledby': 'principles-title',
  },
  children: <HtmlNode>[
    element(
      'div',
      attributes: const <String, String?>{'class': 'section-heading'},
      children: <HtmlNode>[
        element(
          'p',
          attributes: const <String, String?>{'class': 'eyebrow'},
          children: <HtmlNode>[text('A small, explicit core')],
        ),
        element(
          'h2',
          attributes: const <String, String?>{'id': 'principles-title'},
          children: <HtmlNode>[text('The framework stays out of your way.')],
        ),
      ],
    ),
    element(
      'div',
      attributes: const <String, String?>{'class': 'principle-list'},
      children: <HtmlNode>[
        _principle(
          '01',
          'Types cross boundaries.',
          'Routes, inputs, outputs, and data stay explicit from client to server.',
        ),
        _principle(
          '02',
          'Platform code stays at the edge.',
          'The shared application model never imports a runtime-specific adapter.',
        ),
        _principle(
          '03',
          'Runtime wiring stays explicit.',
          'Entrypoints and modules limit reachable Dart code; the one package '
              'still resolves one shared dependency graph.',
        ),
      ],
    ),
  ],
);

HtmlElement _principle(String number, String title, String body) => element(
  'article',
  children: <HtmlNode>[
    element(
      'span',
      attributes: const <String, String?>{'class': 'principle-number'},
      children: <HtmlNode>[text(number)],
    ),
    element('h3', children: <HtmlNode>[text(title)]),
    element('p', children: <HtmlNode>[text(body)]),
  ],
);

HtmlElement _output() => element(
  'section',
  attributes: const <String, String?>{
    'class': 'output section',
    'aria-labelledby': 'output-title',
  },
  children: <HtmlNode>[
    element(
      'div',
      attributes: const <String, String?>{'class': 'output-copy'},
      children: <HtmlNode>[
        element(
          'p',
          attributes: const <String, String?>{'class': 'eyebrow'},
          children: <HtmlNode>[text('One command surface')],
        ),
        element(
          'h2',
          attributes: const <String, String?>{'id': 'output-title'},
          children: <HtmlNode>[text('Small surface. Explicit targets.')],
        ),
        element(
          'p',
          children: <HtmlNode>[
            text(
              'Keep routes and contracts shared, then explicitly choose a '
              'Flutter target, native server, or Preview Cloudflare Worker.',
            ),
          ],
        ),
        element(
          'div',
          attributes: const <String, String?>{'class': 'command-block'},
          children: <HtmlNode>[
            element(
              'code',
              children: <HtmlNode>[text(r'$ dart run odroe init')],
            ),
            element(
              'code',
              children: <HtmlNode>[text(r'$ dart run odroe dev -- -d chrome')],
            ),
            element(
              'code',
              children: <HtmlNode>[
                text(r'$ dart run odroe build --no-server web'),
              ],
            ),
            element(
              'code',
              children: <HtmlNode>[
                text(r'$ dart run odroe build --server-only'),
              ],
            ),
          ],
        ),
        _button('Read the docs', '/docs/getting-started', primary: true),
      ],
    ),
    element(
      'div',
      attributes: const <String, String?>{'class': 'artifact-list'},
      children: <HtmlNode>[
        _artifact(
          'Static',
          'Verified locally',
          'Semantic HTML + Flutter Web',
          'Prerender document routes and copy public assets.',
          'document',
        ),
        _artifact(
          'Native',
          'Verified locally',
          'Dart server executable',
          'Run the same typed server on a VM or container.',
          'server',
        ),
        _artifact(
          'Fetch',
          'Preview',
          'Edge JavaScript',
          'Build a Worker artifact with optional local Workerd verification.',
          'cloud',
        ),
      ],
    ),
  ],
);

HtmlElement _artifact(
  String title,
  String status,
  String output,
  String body,
  String icon,
) => element(
  'article',
  attributes: const <String, String?>{'class': 'artifact'},
  children: <HtmlNode>[
    _icon(icon),
    element(
      'div',
      children: <HtmlNode>[
        element(
          'p',
          attributes: const <String, String?>{'class': 'artifact-kicker'},
          children: <HtmlNode>[
            element('strong', children: <HtmlNode>[text(title)]),
            element('span', children: <HtmlNode>[text(status)]),
          ],
        ),
        element('h3', children: <HtmlNode>[text(output)]),
        element('p', children: <HtmlNode>[text(body)]),
      ],
    ),
  ],
);

HtmlElement _closing() => element(
  'section',
  attributes: const <String, String?>{
    'class': 'closing section',
    'aria-labelledby': 'closing-title',
  },
  children: <HtmlNode>[
    element(
      'p',
      attributes: const <String, String?>{'class': 'eyebrow'},
      children: <HtmlNode>[text('Start with the product, not configuration')],
    ),
    element(
      'h2',
      attributes: const <String, String?>{'id': 'closing-title'},
      children: <HtmlNode>[text('Build the whole product in Dart.')],
    ),
    element(
      'p',
      children: <HtmlNode>[
        text('Start with one package. Compose only the modules you use.'),
      ],
    ),
    _button('Get started', '/docs/getting-started', primary: true),
  ],
);

HtmlElement _button(String label, String href, {bool primary = false}) =>
    element(
      'a',
      attributes: <String, String?>{
        'class': primary ? 'button primary' : 'button',
        'href': href,
      },
      children: <HtmlNode>[text(label)],
    );

HtmlElement _icon(String name) {
  final children = switch (name) {
    'phone' => <HtmlNode>[
      element(
        'rect',
        attributes: const <String, String?>{
          'x': '7',
          'y': '2',
          'width': '10',
          'height': '20',
          'rx': '2',
        },
      ),
      element('path', attributes: const <String, String?>{'d': 'M10 18h4'}),
    ],
    'globe' => <HtmlNode>[
      element(
        'circle',
        attributes: const <String, String?>{'cx': '12', 'cy': '12', 'r': '9'},
      ),
      element(
        'path',
        attributes: const <String, String?>{
          'd': 'M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18',
        },
      ),
    ],
    'server' => <HtmlNode>[
      element(
        'rect',
        attributes: const <String, String?>{
          'x': '3',
          'y': '3',
          'width': '18',
          'height': '18',
          'rx': '2',
        },
      ),
      element(
        'path',
        attributes: const <String, String?>{
          'd': 'M3 11h18M7 7h.01M7 15h.01M11 7h6M11 15h6',
        },
      ),
    ],
    'database' => <HtmlNode>[
      element(
        'ellipse',
        attributes: const <String, String?>{
          'cx': '12',
          'cy': '5',
          'rx': '8',
          'ry': '3',
        },
      ),
      element(
        'path',
        attributes: const <String, String?>{
          'd': 'M4 5v7c0 2 4 3 8 3s8-1 8-3V5M4 12v7c0 2 4 3 8 3s8-1 8-3v-7',
        },
      ),
    ],
    'cloud' => <HtmlNode>[
      element(
        'path',
        attributes: const <String, String?>{
          'd': 'M7 19h11a4 4 0 0 0 .5-8 7 7 0 0 0-13.6 1.8A3.2 3.2 0 0 0 7 19Z',
        },
      ),
    ],
    'document' => <HtmlNode>[
      element(
        'path',
        attributes: const <String, String?>{
          'd': 'M6 2h8l4 4v16H6zM14 2v5h5M9 12h6M9 16h6',
        },
      ),
    ],
    _ => <HtmlNode>[
      element(
        'path',
        attributes: const <String, String?>{'d': 'M6 2h8l4 4v16H6zM14 2v5h5'},
      ),
    ],
  };
  return element(
    'svg',
    attributes: const <String, String?>{
      'viewBox': '0 0 24 24',
      'aria-hidden': 'true',
      'focusable': 'false',
    },
    children: children,
  );
}
