import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/query_flutter.dart';

void main() {
  testWidgets('QueryBuilder fetches through the inherited client', (
    tester,
  ) async {
    final client = QueryClient();
    final options = QueryOptions<int>(
      key: QueryKey('widget'),
      policy: const QueryPolicy(gcTime: Duration.zero),
      query: (_) => 42,
    );

    await tester.pumpWidget(
      QueryClientProvider(
        client: client,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            options: options,
            builder: (context, result) =>
                Text(result.hasData ? '${result.requireData}' : 'loading'),
          ),
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);

    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });
}
