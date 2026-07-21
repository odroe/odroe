import 'package:odroe/mdc.dart';
import 'package:test/test.dart';

void main() {
  test('parses one immutable renderer-neutral MDC document', () {
    const parser = MdcParser();
    final document = parser.parse('''
\u{feff}---
title: Odroe
draft: false
tags: [flutter, dart]
seo:
  score: 9.5
---
# Hello {#intro .hero}

Text with **bold**{.loud}, [marked]{.accent}, and :badge[It's **new**]{count=2 active label='it''s' options={tone: dark}}.

Use {title} and {"a": 1} as ordinary prose.

::callout{tone=info}
---
count: 3
options:
  dense: true
---
Default before slots.

```text
#not-a-slot
::
```

#icon{size=24}
:icon{name=spark}

#default
Default after the slot with :empty{}.

:::nested{level=2}
Nested content.
:::
::

<script>alert("x")</script>
''');

    expect(document.frontmatter, <String, Object?>{
      'title': 'Odroe',
      'draft': false,
      'tags': <Object?>['flutter', 'dart'],
      'seo': <String, Object?>{'score': 9.5},
    });

    final heading = document.nodes.whereType<MdcElement>().firstWhere(
      (node) => node.tag == 'h1',
    );
    expect(heading.attributes, <String, String?>{
      'id': 'intro',
      'class': 'hero',
    });

    final paragraph = document.nodes.whereType<MdcElement>().firstWhere(
      (node) => node.tag == 'p',
    );
    final strong = paragraph.children.whereType<MdcElement>().firstWhere(
      (node) => node.tag == 'strong',
    );
    final span = paragraph.children.whereType<MdcElement>().firstWhere(
      (node) => node.tag == 'span',
    );
    final badge = paragraph.children.whereType<MdcComponent>().single;
    expect(strong.attributes['class'], 'loud');
    expect(span.attributes['class'], 'accent');
    expect(badge.name, 'badge');
    expect(badge.properties, <String, Object?>{
      'count': 2,
      'active': true,
      'label': "it's",
      'options': <String, Object?>{'tone': 'dark'},
    });

    final callout = document.nodes.whereType<MdcComponent>().single;
    expect(callout.name, 'callout');
    expect(callout.properties, <String, Object?>{
      'tone': 'info',
      'count': 3,
      'options': <String, Object?>{'dense': true},
    });
    expect(callout.slots.keys, <String>['icon']);
    expect(callout.slots['icon']!.properties, <String, Object?>{'size': 24});
    expect(_components(callout.children).map((node) => node.name), <String>[
      'empty',
      'nested',
    ]);
    expect(_text(document.nodes), contains('Use {title} and {"a": 1}'));
    expect(_text(callout.children), contains('#not-a-slot\n::'));

    expect(_text(document.nodes), contains('<script>alert("x")</script>'));
    expect(
      _elements(document.nodes).any((node) => node.tag == 'script'),
      isFalse,
    );
    expect(() => document.frontmatter['other'] = true, throwsUnsupportedError);
    expect(
      () => (document.frontmatter['tags']! as List<Object?>).add('web'),
      throwsUnsupportedError,
    );
    expect(
      () => MdcDocument(
        frontmatter: <String, Object?>{
          'invalid': <Object?, Object?>{1: 'value'},
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => parser.parse(':button[Run]{@click=run}'),
      throwsFormatException,
    );
    expect(
      () => parser.parse('''
::card{title=inline}
---
title: yaml
---
::
'''),
      throwsFormatException,
    );
  });
}

Iterable<MdcComponent> _components(Iterable<MdcNode> nodes) sync* {
  for (final node in nodes) {
    if (node is MdcComponent) {
      yield node;
      yield* _components(node.children);
      for (final slot in node.slots.values) {
        yield* _components(slot.children);
      }
    } else if (node is MdcElement) {
      yield* _components(node.children);
    }
  }
}

Iterable<MdcElement> _elements(Iterable<MdcNode> nodes) sync* {
  for (final node in nodes) {
    if (node is MdcElement) {
      yield node;
      yield* _elements(node.children);
    } else if (node is MdcComponent) {
      yield* _elements(node.children);
      for (final slot in node.slots.values) {
        yield* _elements(slot.children);
      }
    }
  }
}

String _text(Iterable<MdcNode> nodes) {
  final buffer = StringBuffer();
  for (final node in nodes) {
    if (node is MdcText) {
      buffer.write(node.value);
    } else if (node is MdcElement) {
      buffer.write(_text(node.children));
    } else if (node is MdcComponent) {
      buffer.write(_text(node.children));
      for (final slot in node.slots.values) {
        buffer.write(_text(slot.children));
      }
    }
  }
  return buffer.toString();
}
