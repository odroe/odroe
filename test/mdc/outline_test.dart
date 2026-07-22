import 'package:odroe/mdc.dart';
import 'package:test/test.dart';

void main() {
  test('heading IDs and outline stay stable across nested MDC content', () {
    final untouched = MdcElement(
      'p',
      children: const <MdcNode>[MdcText('Body')],
    );
    final source = MdcDocument(
      nodes: <MdcNode>[
        MdcElement('h1', children: const <MdcNode>[MdcText('Overview')]),
        untouched,
        MdcElement(
          'h2',
          attributes: const <String, String?>{'id': 'overview'},
          children: const <MdcNode>[MdcText('Explicit')],
        ),
        MdcElement(
          'h2',
          children: <MdcNode>[
            const MdcText('快速 '),
            MdcElement('em', children: <MdcNode>[MdcText('开始')]),
          ],
        ),
        MdcComponent(
          'Section',
          children: <MdcNode>[
            MdcElement('h2', children: const <MdcNode>[MdcText('Overview')]),
          ],
          slots: <String, MdcSlot>{
            'details': MdcSlot(
              children: <MdcNode>[
                MdcElement('h3', children: const <MdcNode>[MdcText('Details')]),
              ],
            ),
          },
        ),
      ],
    );

    final indexed = source.withHeadingIds();
    final nodes = indexed.nodes;
    expect((nodes[0] as MdcElement).attributes['id'], 'overview-2');
    expect(nodes[1], same(untouched));
    expect((nodes[2] as MdcElement).attributes['id'], 'overview');
    expect((nodes[3] as MdcElement).attributes['id'], '快速-开始');

    final component = nodes[4] as MdcComponent;
    expect(
      (component.children.single as MdcElement).attributes['id'],
      'overview-3',
    );
    expect(
      (component.slots['details']!.children.single as MdcElement)
          .attributes['id'],
      'details',
    );

    final outline = indexed.outline;
    expect(outline, hasLength(1));
    expect(outline.single.id, 'overview-2');
    expect(outline.single.title, 'Overview');
    expect(outline.single.children.map((entry) => entry.id), <String>[
      'overview',
      '快速-开始',
      'overview-3',
    ]);
    expect(outline.single.children.last.children.single.id, 'details');
    expect(() => outline.add(outline.single), throwsUnsupportedError);
    expect(
      () => outline.single.children.add(outline.single),
      throwsUnsupportedError,
    );
  });

  test('documents without generated heading IDs are reused', () {
    final document = MdcDocument(
      nodes: <MdcNode>[
        MdcElement(
          'h2',
          attributes: const <String, String?>{'id': 'ready'},
          children: const <MdcNode>[MdcText('Ready')],
        ),
      ],
    );

    expect(document.withHeadingIds(), same(document));
    expect(document.outline.single.id, 'ready');
  });

  test('parser transforms run before automatic heading IDs', () {
    final parser = MdcParser(transforms: <MdcTransform>[_appendHeading]);
    final document = parser.parse('Body');

    final heading = document.nodes.last as MdcElement;
    expect(heading.attributes['id'], 'from-transform');
    expect(document.outline.single.title, 'From transform');

    final plain = const MdcParser(headingIds: false).parse('# Plain');
    expect((plain.nodes.single as MdcElement).attributes['id'], isNull);
  });
}

MdcDocument _appendHeading(MdcDocument document) => MdcDocument(
  frontmatter: document.frontmatter,
  nodes: <MdcNode>[
    ...document.nodes,
    MdcElement('h2', children: const <MdcNode>[MdcText('From transform')]),
  ],
);
