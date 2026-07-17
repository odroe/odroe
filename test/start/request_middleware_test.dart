import 'dart:convert';

import 'package:odroe/start.dart';
import 'package:test/test.dart';

void main() {
  test(
    'headers are case-insensitive and request bodies enforce limits',
    () async {
      final headers = StartHeaders.single(<String, String>{
        'Content-Type': 'text',
      });
      headers.append('content-type', 'charset=utf-8');
      expect(headers.value('CONTENT-TYPE'), 'text, charset=utf-8');

      final request = StartRequest.bytes(
        method: StartMethod.post,
        uri: Uri.parse('http://localhost/upload'),
        body: utf8.encode('12345'),
      );
      await expectLater(
        request.readBytes(maxBytes: 4),
        throwsA(isA<StartPayloadTooLargeException>()),
      );
    },
  );

  test(
    'middleware is nested in stable order and shares typed context',
    () async {
      const user = StartContextKey<String>('user');
      final order = <String>[];
      final context = StartRequestContext(
        request: StartRequest.bytes(
          method: StartMethod.get,
          uri: Uri.parse('http://localhost/'),
        ),
        query: QueryClient(),
        type: StartHandlerType.router,
      );

      final response = await runStartMiddleware(
        context,
        <StartMiddleware>[
          (context, next) async {
            order.add('a.before');
            context.set(user, 'Ada');
            final response = await next();
            order.add('a.after');
            return response;
          },
          (context, next) async {
            order.add('b.${context.require(user)}');
            return next();
          },
        ],
        () {
          order.add('handler');
          return StartResponse.text('ok');
        },
      );

      expect(await response.readText(), 'ok');
      expect(order, <String>['a.before', 'b.Ada', 'handler', 'a.after']);
    },
  );

  test('default CSRF middleware rejects unprovable RPC origins', () async {
    final middleware = const StartCsrfMiddleware();
    final context = StartRequestContext(
      request: StartRequest.bytes(
        method: StartMethod.post,
        uri: Uri.parse('https://app.example/functions'),
      ),
      query: QueryClient(),
      type: StartHandlerType.serverFunction,
    );

    final response = await middleware.call(
      context,
      () async => StartResponse.text('ok'),
    );
    expect(response.status, 403);
  });
}
