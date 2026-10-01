import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart';

void main() {
  testWidgets('lazy module enumeration rolls back yielded resources', (
    tester,
  ) async {
    final failure = StateError('module enumeration failed');
    final events = <String>[];

    Iterable<Module> modules() sync* {
      yield _LifecycleModule(events);
      throw failure;
    }

    await tester.pumpWidget(
      App(
        modules: modules(),
        builder: (_) => const SizedBox.shrink(),
        errorBuilder: (error, _) {
          expect(error, same(failure));
          return const Text('failed', textDirection: TextDirection.ltr);
        },
      ),
    );
    await tester.pump();

    expect(find.text('failed'), findsOneWidget);
    expect(events, <String>['dispose']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting an initialization failure adds no uncaught error', (
    tester,
  ) async {
    await tester.pumpWidget(
      App(
        modules: <Module>[_InitializeFailureModule()],
        builder: (_) => const SizedBox.shrink(),
        errorBuilder: (_, _) =>
            const Text('failed', textDirection: TextDirection.ltr),
      ),
    );
    await tester.pump();
    expect(find.text('failed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a disposal failure is reported exactly once', (tester) async {
    final failure = StateError('dispose failed');
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      App(
        modules: <Module>[_DisposeFailureModule(failure)],
        builder: (_) => const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    FlutterError.onError = reports.add;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(failure));
    expect(reports.single.library, 'odroe');
  });
}

final class _LifecycleModule extends Module {
  _LifecycleModule(this.events);

  final List<String> events;

  @override
  void register(ModuleRegistry registry) {}

  @override
  void dispose(AppContext context) {
    events.add('dispose');
  }
}

final class _InitializeFailureModule extends Module {
  @override
  void register(ModuleRegistry registry) {}

  @override
  void initialize(AppContext context) {
    throw StateError('initialize failed');
  }
}

final class _DisposeFailureModule extends Module {
  _DisposeFailureModule(this.failure);

  final Object failure;

  @override
  void register(ModuleRegistry registry) {}

  @override
  Future<void> dispose(AppContext context) async {
    throw failure;
  }
}
