import 'package:odroe/document.dart';
import 'package:odroe/mdc.dart';
import 'package:odroe/odroe.dart';
import 'package:test/test.dart';

void main() {
  final callout = MdcHtmlComponent('Callout', (context) {
    return HtmlElement(
      'aside',
      attributes: const <String, String?>{'class': 'callout'},
      children: <HtmlNode>[
        context.slots['title']?.children ?? const HtmlFragment(<HtmlNode>[]),
        context.children,
      ],
    );
  });

  test('HTML rendering is semantic, component-aware, and URL-safe', () {
    const uriPolicy = MdcUriPolicy();
    expect(uriPolicy.link('/guide'), '/guide');
    expect(uriPolicy.link('//untrusted.example'), isNull);
    expect(uriPolicy.link(r'/\untrusted.example'), isNull);

    final document = MdcDocument(
      nodes: <MdcNode>[
        MdcElement(
          'a',
          attributes: const <String, String?>{
            'href': 'javascript:alert(1)',
            'onclick': 'alert(1)',
            'target': '_blank',
          },
          children: const <MdcNode>[MdcText('<safe>')],
        ),
        MdcElement(
          'img',
          attributes: const <String, String?>{
            'src': 'data:image/svg+xml,unsafe',
            'alt': 'Avatar',
          },
        ),
        MdcComponent(
          'Callout',
          properties: const <String, Object?>{'tone': 'info'},
          children: const <MdcNode>[MdcText('Body')],
          slots: <String, MdcSlot>{
            'title': MdcSlot(children: const <MdcNode>[MdcText('Title')]),
          },
        ),
      ],
    );

    final body = MdcHtmlRenderer(
      components: <MdcHtmlComponent>[callout],
    ).render(document);
    final html = renderDocumentStart(
      resolveDocument(<RouteDocument>[RouteDocument(body: body)]),
    );

    expect(
      html,
      contains('<a target="_blank" rel="noopener noreferrer">&lt;safe&gt;</a>'),
    );
    expect(html, contains('<img alt="Avatar">'));
    expect(html, contains('<aside class="callout">TitleBody</aside>'));
    expect(html, isNot(contains('javascript:')));
    expect(html, isNot(contains('onclick')));
    expect(html, isNot(contains('tone=')));
  });

  test('components are strict and module registrations are unique', () async {
    expect(
      () => MdcHtmlRenderer().render(
        MdcDocument(nodes: <MdcNode>[MdcComponent('Missing')]),
      ),
      throwsA(isA<MdcUnknownComponentException>()),
    );

    final app = await AppContext.create(<Module>[
      MdcModule(components: <MdcComponentBinding>[callout]),
    ]);
    expect(app.read(mdcParserKey), isA<MdcParser>());
    expect(
      MdcHtmlRenderer.fromApp(
        app,
      ).render(MdcDocument(nodes: <MdcNode>[MdcComponent('Callout')])),
      isA<HtmlFragment>(),
    );
    await app.dispose();

    await expectLater(
      AppContext.create(<Module>[
        MdcModule(components: <MdcComponentBinding>[callout]),
        MdcModule(components: <MdcComponentBinding>[callout]),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects inputs that are not task-list checkboxes', () {
    expect(
      () => MdcHtmlRenderer().render(
        MdcDocument(nodes: <MdcNode>[MdcElement('input')]),
      ),
      throwsA(isA<MdcHtmlRenderException>()),
    );
  });
}
