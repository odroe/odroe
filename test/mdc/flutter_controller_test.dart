import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/src/mdc/ast.dart';
import 'package:odroe/src/mdc_flutter/controller.dart';

void main() {
  test('controller reparses only effective complete-source changes', () {
    final controller = MdcDocumentController(source: '# One');
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final initial = controller.document;
    controller.replace('# One');
    expect(controller.document, same(initial));
    expect(notifications, 0);

    controller.append('\n\nBody');
    expect(controller.source, '# One\n\nBody');
    expect(controller.document, isNot(same(initial)));
    expect(controller.document.nodes, hasLength(2));
    expect(controller.document.nodes.first, isA<MdcElement>());
    expect(notifications, 1);

    final appended = controller.document;
    controller.append('');
    expect(controller.document, same(appended));
    expect(notifications, 1);

    controller.replace('Final');
    expect(controller.source, 'Final');
    expect(controller.document.nodes, hasLength(1));
    expect(notifications, 2);
  });
}
