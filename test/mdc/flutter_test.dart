import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/mdc_flutter.dart';
import 'package:odroe/odroe_flutter.dart';

void main() {
  testWidgets('MdcView renders the shared AST and module components', (
    tester,
  ) async {
    final callout = MdcWidgetComponent('Callout', (context) {
      return Column(
        children: <Widget>[
          Text('${context.properties['tone']}'),
          context.slots['title']!.children,
          context.children,
        ],
      );
    });
    final document = MdcDocument(
      nodes: <MdcNode>[
        MdcElement('h1', children: const <MdcNode>[MdcText('Shared AST')]),
        MdcComponent(
          'Callout',
          properties: const <String, Object?>{'tone': 'info'},
          children: const <MdcNode>[MdcText('Body')],
          slots: <String, MdcSlot>{
            'title': MdcSlot(children: const <MdcNode>[MdcText('Title')]),
          },
        ),
      ],
    );

    await tester.pumpWidget(
      App(
        modules: <Module>[
          MdcModule(components: <MdcComponentBinding>[callout]),
        ],
        builder: (_) => MaterialApp(
          home: Scaffold(body: MdcView(document: document)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared AST'), findsOneWidget);
    final heading = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.headingLevel == 1,
      ),
    );
    expect(heading.properties.header, isTrue);
    expect(find.text('info'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });
}
