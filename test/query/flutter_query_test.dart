import 'dart:async';

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

  testWidgets('MutationBuilder keeps active state when options change', (
    tester,
  ) async {
    final client = QueryClient();
    final result = Completer<int>();
    var useNextMutation = false;
    var firstCalls = 0;
    var nextCalls = 0;
    late StateSetter rebuild;
    late Future<int> Function(int variables) mutate;

    await tester.pumpWidget(
      App(
        modules: <Module>[QueryModule(client: client)],
        builder: (_) => Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MutationBuilder<int, int, void>(
                options: MutationOptions<int, int, void>(
                  key: QueryKey('save'),
                  mutation: useNextMutation
                      ? (value, _) {
                          nextCalls++;
                          return value * 2;
                        }
                      : (_, _) {
                          firstCalls++;
                          return result.future;
                        },
                ),
                builder: (_, state, run, _) {
                  mutate = run;
                  return Text(state.status.name);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('idle'), findsOneWidget);
    unawaited(mutate(1));
    await tester.pump();
    expect(find.text('pending'), findsOneWidget);
    expect(firstCalls, 1);

    useNextMutation = true;
    rebuild(() {});
    await tester.pump();
    expect(find.text('pending'), findsOneWidget);

    result.complete(42);
    await tester.pump();
    await tester.pump();
    expect(find.text('success'), findsOneWidget);

    expect(await mutate(21), 42);
    await tester.pump();
    await tester.pump();
    expect(nextCalls, 1);
    expect(find.text('success'), findsOneWidget);

    client.clear();
  });
}
