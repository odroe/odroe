import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('same-name request keys keep independent values', () async {
    final app = AppContext.empty();
    try {
      final context = _context(app);
      final first = RequestKey<String>('user');
      final second = RequestKey<String>('user');

      first.set(context, 'first');
      second.set(context, 'second');

      expect(first, isNot(same(second)));
      expect(context.require(first), 'first');
      expect(context.require(second), 'second');
    } finally {
      await app.dispose();
    }
  });

  test('widened request keys enforce their runtime value type', () async {
    final app = AppContext.empty();
    try {
      final context = _context(app);
      final key = RequestKey<String>('user');
      final RequestKey<Object?> widened = key;

      expect(() => widened.set(context, 42), throwsA(isA<TypeError>()));
      expect(context.contains(key), isFalse);

      widened.set(context, 'user');
      expect(context.require(key), 'user');
    } finally {
      await app.dispose();
    }
  });
}

RequestContext _context(AppContext app) => RequestContext(
  request: ServerRequest(
    method: HttpMethod.get,
    uri: Uri(path: '/'),
  ),
  app: app,
);
