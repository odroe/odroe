import 'package:odroe/mdc.dart';
import 'package:odroe/press.dart';
import 'package:test/test.dart';

void main() {
  test('orders, finds, and renders immutable pages', () {
    final later = _page(
      slug: const <String>['later'],
      title: 'Later',
      order: 2,
    );
    final first = _page(
      slug: const <String>['first'],
      title: 'First',
      order: 1,
    );
    final press = Press(<PressPage>[later, first]);

    expect(press.pages, <PressPage>[first, later]);
    expect(press.page(const <String>['later']), same(later));
    expect(press.locations, <Uri>[Uri(path: '/first'), Uri(path: '/later')]);
    expect(
      first
          .toDocument(canonicalOrigin: Uri.parse('https://odroe.dev'))
          .canonical,
      'https://odroe.dev/first',
    );
    expect(
      MdcHtmlRenderer().render(first.content).children.single,
      isA<HtmlElement>(),
    );
    expect(() => press.pages.add(first), throwsUnsupportedError);
    expect(
      () => press.locations.add(Uri(path: '/other')),
      throwsUnsupportedError,
    );
    expect(() => first.slug.add('other'), throwsUnsupportedError);
  });

  test('preserves and deeply freezes application frontmatter', () {
    final source = <String, Object?>{
      'title': 'Extensible',
      'navigation': <String, Object?>{
        'tags': <Object?>['framework', 'flutter'],
      },
    };
    final page = _page(
      slug: const <String>['extensible'],
      title: 'Extensible',
      content: MdcDocument(
        frontmatter: source,
        nodes: const <MdcNode>[MdcText('Body')],
      ),
    );
    source['navigation'] = 'changed';

    final navigation = page.frontmatter['navigation']! as Map<String, Object?>;
    final tags = navigation['tags']! as List<Object?>;
    expect(tags, <Object?>['framework', 'flutter']);
    expect(
      () => page.frontmatter['application'] = true,
      throwsUnsupportedError,
    );
    expect(() => navigation['other'] = true, throwsUnsupportedError);
    expect(() => tags.add('server'), throwsUnsupportedError);
  });

  test('rejects case-insensitive duplicate slugs and locations', () {
    expect(
      () => Press(<PressPage>[
        _page(slug: const <String>['Docs'], title: 'One'),
        _page(slug: const <String>['docs'], title: 'Two'),
      ]),
      throwsArgumentError,
    );
    expect(
      () => Press(<PressPage>[
        _page(
          slug: const <String>['first'],
          location: Uri(path: '/Guide'),
          title: 'One',
        ),
        _page(
          slug: const <String>['second'],
          location: Uri(path: '/guide'),
          title: 'Two',
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('rejects invalid canonical origins', () {
    final page = _page(slug: const <String>['docs'], title: 'Docs');
    for (final origin in <Uri>[
      Uri.parse('/relative'),
      Uri.parse('//odroe.dev'),
      Uri.parse('ftp://odroe.dev'),
      Uri.parse('https://user@odroe.dev'),
      Uri.parse('https://odroe.dev/base'),
      Uri.parse('https://odroe.dev?draft=true'),
      Uri.parse('https://odroe.dev/#intro'),
    ]) {
      expect(
        () => page.toDocument(canonicalOrigin: origin),
        throwsArgumentError,
        reason: '$origin',
      );
    }
  });
}

PressPage _page({
  required List<String> slug,
  required String title,
  Uri? location,
  int order = 0,
  MdcDocument? content,
}) => PressPage(
  slug: slug,
  location: location ?? Uri(pathSegments: <String>['', ...slug]),
  title: title,
  order: order,
  content: content ?? MdcParser().parse('# $title'),
  sourcePath: '${slug.join('/')}.mdc',
);
