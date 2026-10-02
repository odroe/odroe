import 'package:odroe/document.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loader-derived invalid names fail before returning executable HTML',
    () async {
      final errors = <Object>[];
      final route = AppRoute<NoParams, NoSearch, String>(path: '/')
          .document((context) => RouteDocument(body: HtmlElement(context.data)))
          .server(load: (_) => 'img src=x onerror=alert(1)');
      final app = Server(
        routes: [route],
        renderer: const DocumentRenderer().call,
        onError: (_, error, _) => errors.add(error),
      );
      final response = await app.handle(
        ServerRequest.bytes(
          method: HttpMethod.get,
          uri: Uri.parse('http://localhost/'),
          headers: Headers.single({'accept': 'text/html'}),
        ),
      );
      final body = await response.readText();
      await app.close();
      expect(response.status, 500);
      expect(body, isNot(contains('onerror')));
      expect(errors, [isA<ArgumentError>()]);
    },
  );

  test('document rendering rejects markup in element names', () {
    for (final tag in <String>[
      '',
      'img src=x onerror=alert(1)',
      'div><script>alert(1)</script',
      'div\nclass',
      'div\u0000',
      '/div',
      '0div',
      'div"',
      'div\u007f',
    ]) {
      expect(
        () => renderDocumentStart(
          resolveDocument(<RouteDocument>[
            RouteDocument(body: HtmlElement(tag)),
          ]),
        ),
        throwsArgumentError,
        reason: tag,
      );
    }
  });

  test('document rendering rejects invalid attribute names on every owner', () {
    for (final name in <String>[
      '',
      'x onmouseover',
      'x\tonclick',
      'x\nonclick',
      'x=onclick',
      'x"onclick',
      "x'onclick",
      'x/onload',
      'x><script',
      'x\u0000',
      'x\u007f',
      'x\u0080',
      'x\ufdd0',
      'x\ufffe',
    ]) {
      for (final document in <RouteDocument>[
        RouteDocument(body: HtmlElement('div', attributes: {name: 'alert(1)'})),
        RouteDocument(body: HtmlElement('div', attributes: {name: null})),
        RouteDocument(htmlAttributes: {name: 'value'}),
        RouteDocument(bodyAttributes: {name: 'value'}),
      ]) {
        expect(
          () => renderDocumentStart(resolveDocument([document])),
          throwsArgumentError,
          reason: name,
        );
      }
    }
  });

  test('valid custom, foreign and application attribute names remain usable', () {
    final html = renderDocumentStart(
      resolveDocument(const <RouteDocument>[
        RouteDocument(
          htmlAttributes: {'lang': 'en'},
          body: HtmlElement(
            'my-元素',
            attributes: {
              'data-id': 'one',
              'aria-label': '<label>',
              '@click': 'selected',
              'étiquette': 'two',
            },
            children: [
              HtmlElement(
                'svg',
                attributes: {'viewBox': '0 0 1 1'},
                children: [
                  HtmlElement(
                    'linearGradient',
                    attributes: {'xlink:href': '#gradient'},
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
    expect(
      html,
      contains(
        '<my-元素 data-id="one" aria-label="&lt;label&gt;" @click="selected" étiquette="two">',
      ),
    );
    expect(
      html,
      contains(
        '<svg viewBox="0 0 1 1"><linearGradient xlink:href="#gradient">',
      ),
    );
  });
}
