import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oref/oref.dart';

Widget wrapWithDirectionality(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('provide and inject tests', () {
    testWidgets('provide and inject basic functionality',
        (WidgetTester tester) async {
      const testKey = Symbol('testKey');
      const testValue = 'Test Value';

      await tester.pumpWidget(
        wrapWithDirectionality(
          Builder(
            builder: (context) {
              provide(context, testKey, testValue);
              return Builder(
                builder: (context) {
                  final injectedValue = inject<String>(context, testKey);
                  expect(injectedValue, equals(testValue));
                  return Text(injectedValue ?? 'Not found');
                },
              );
            },
          ),
        ),
      );

      expect(find.text(testValue), findsOneWidget);
    });

    testWidgets('provide and inject with different types',
        (WidgetTester tester) async {
      const stringKey = Symbol('stringKey');
      const stringValue = 'String Value';
      const intKey = Symbol('intKey');
      const intValue = 42;

      await tester.pumpWidget(
        wrapWithDirectionality(
          Builder(
            builder: (context) {
              provide(context, stringKey, stringValue);
              provide(context, intKey, intValue);
              return Column(
                children: [
                  Builder(
                    builder: (context) {
                      final injectedString = inject<String>(context, stringKey);
                      return Text('String: ${injectedString ?? 'Not found'}');
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final injectedInt = inject<int>(context, intKey);
                      return Text('Int: ${injectedInt ?? 'Not found'}');
                    },
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('String: $stringValue'), findsOneWidget);
      expect(find.text('Int: $intValue'), findsOneWidget);
    });

    testWidgets('inject inherits from parent', (WidgetTester tester) async {
      const parentKey = Symbol('parentKey');
      const parentValue = 'Parent Value';
      const childKey = Symbol('childKey');
      const childValue = 'Child Value';

      await tester.pumpWidget(
        wrapWithDirectionality(
          Builder(
            builder: (context) {
              provide(context, parentKey, parentValue);
              return Builder(
                builder: (childContext) {
                  provide(childContext, childKey, childValue);
                  return Column(
                    children: [
                      Builder(
                        builder: (context) {
                          final injectedParentValue =
                              inject<String>(context, parentKey);
                          return Text(
                              'Parent: ${injectedParentValue ?? 'Not found'}');
                        },
                      ),
                      Builder(
                        builder: (context) {
                          final injectedChildValue =
                              inject<String>(context, childKey);
                          return Text(
                              'Child: ${injectedChildValue ?? 'Not found'}');
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );

      expect(find.text('Parent: $parentValue'), findsOneWidget);
      expect(find.text('Child: $childValue'), findsOneWidget);
    });

    testWidgets('widget rebuilds when provided value changes',
        (WidgetTester tester) async {
      const testKey = Symbol('testKey');
      const initialValue = 'Initial Value';
      const updatedValue = 'Updated Value';
      late BuildContext provideContext;

      Widget buildTestWidget(String value) {
        return wrapWithDirectionality(
          StatefulBuilder(
            builder: (context, setState) {
              provideContext = context;
              provide(context, testKey, value);
              return Builder(
                builder: (childContext) {
                  final currentValue = inject<String>(childContext, testKey);
                  return Text(currentValue ?? 'Not found');
                },
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget(initialValue));
      expect(find.text(initialValue), findsOneWidget);

      provide(provideContext, testKey, updatedValue);
      await tester.pump();
      expect(find.text(updatedValue), findsOneWidget);
    });
  });
}
