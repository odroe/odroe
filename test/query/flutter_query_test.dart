import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';

void main() {
  testWidgets('QueryModule installs its client for Flutter query widgets', (
    tester,
  ) async {
    final client = QueryClient();
    final options = QueryOptions<int>(
      key: QueryKey('widget'),
      policy: const QueryPolicy(gcTime: Duration.zero),
      query: (_) => 42,
    );

    await tester.pumpWidget(
      App(
        modules: <Module>[QueryModule(client: client)],
        builder: (app) {
          expect(app.read(queryClientKey), same(client));
          return Directionality(
            textDirection: TextDirection.ltr,
            child: QueryBuilder<int>(
              options: options,
              builder: (context, result) =>
                  Text(result.hasData ? '${result.requireData}' : 'loading'),
            ),
          );
        },
      ),
    );

    await tester.pump();
    expect(find.text('loading'), findsOneWidget);

    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });
}
