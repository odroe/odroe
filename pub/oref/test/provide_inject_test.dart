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
              final injectedValue = inject<String>(context, testKey);
              expect(injectedValue, equals(testValue));
              return const SizedBox();
            },
          ),
        ),
      );
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

              final injectedString = inject<String>(context, stringKey);
              final injectedInt = inject<int>(context, intKey);

              expect(injectedString, equals(stringValue));
              expect(injectedInt, equals(intValue));
              return const SizedBox();
            },
          ),
        ),
      );
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
                  final injectedParentValue =
                      inject<String>(childContext, parentKey);
                  final injectedChildValue =
                      inject<String>(childContext, childKey);
                  expect(injectedParentValue, equals(parentValue));
                  expect(injectedChildValue, equals(childValue));
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
    });

    testWidgets('widget rebuilds when provided value changes',
        (WidgetTester tester) async {
      const testKey = Symbol('testKey');
      const initialValue = 'Initial Value';
      const updatedValue = 'Updated Value';
      late String currentValue;

      Widget buildTestWidget(String value) {
        return wrapWithDirectionality(
          Builder(
            builder: (context) {
              provide(context, testKey, value);
              return Builder(
                builder: (childContext) {
                  currentValue = inject<String>(childContext, testKey)!;
                  return Text(currentValue);
                },
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget(initialValue));
      expect(find.text(initialValue), findsOneWidget);
      expect(currentValue, equals(initialValue));

      await tester.pumpWidget(buildTestWidget(updatedValue));
      expect(find.text(updatedValue), findsOneWidget);
      expect(currentValue, equals(updatedValue));
    });
  });
}
