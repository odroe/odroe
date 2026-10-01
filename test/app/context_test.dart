import 'dart:async';

import 'package:odroe/odroe.dart';
import 'package:test/test.dart';

final _valueKey = ContextKey<Object>('value');
final _lazyKey = ContextKey<Object>('lazy');

void main() {
  test('an enumeration failure disposes every yielded module', () async {
    final setupFailure = StateError('enumeration failed');
    final events = <String>[];

    Iterable<Module> modules() sync* {
      yield _SetupModule('first', events);
      yield _SetupModule('second', events);
      throw setupFailure;
    }

    await expectLater(
      AppContext.create(modules()),
      throwsA(same(setupFailure)),
    );
    expect(events, <String>['dispose:second', 'dispose:first']);
  });

  for (final phase in _SetupFailurePhase.values) {
    test('a ${phase.name} failure disposes every installed module', () async {
      final setupFailure = StateError('${phase.name} failed');
      final cleanupFailure = StateError('tail cleanup failed');
      final cleanupErrors = <Object>[];
      final events = <String>[];
      final modules = <Module>[
        _SetupModule('first', events),
        _SetupModule(
          'failing',
          events,
          failurePhase: phase,
          setupFailure: setupFailure,
        ),
        _SetupModule('tail', events, disposeFailure: cleanupFailure),
      ];

      await expectLater(
        AppContext.create(
          modules,
          onCleanupError: (error, _) => cleanupErrors.add(error),
        ),
        throwsA(same(setupFailure)),
      );

      expect(
        events,
        phase == _SetupFailurePhase.register
            ? <String>[
                'register:first',
                'register:failing',
                'dispose:tail',
                'dispose:failing',
                'dispose:first',
              ]
            : <String>[
                'register:first',
                'register:failing',
                'register:tail',
                'initialize:first',
                'initialize:failing',
                'dispose:tail',
                'dispose:failing',
                'dispose:first',
              ],
      );
      expect(cleanupErrors, <Object>[cleanupFailure]);
    });
  }

  test('concurrent disposal joins once and reads fail after cleanup', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var disposeCalls = 0;
    var lazyCalls = 0;
    final value = Object();
    final context = await AppContext.create(<Module>[
      _BlockingModule(
        value,
        gate: gate.future,
        onStarted: started.complete,
        onDispose: () => disposeCalls++,
        createLazy: () {
          lazyCalls++;
          return Object();
        },
      ),
    ]);
    final bindingSnapshot = context.bindings<_TestBinding>();

    final first = context.dispose();
    final second = context.dispose();

    expect(second, same(first));
    await started.future;
    expect(disposeCalls, 1);
    expect(context.read(_valueKey), same(value));

    gate.complete();
    await first;

    expect(context.dispose(), same(first));
    expect(() => context.read(_valueKey), throwsStateError);
    expect(() => context.maybe(_lazyKey), throwsStateError);
    expect(() => context.bindings<_TestBinding>(), throwsStateError);
    expect(bindingSnapshot.toList(), hasLength(1));
    expect(lazyCalls, 0);
  });

  test(
    'disposal cannot create a lazy value after its owner releases',
    () async {
      final events = <String>[];
      final errors = <Object>[];
      var factoryCalls = 0;
      final context = await AppContext.create(<Module>[
        _LazyCleanupReader(events, errors),
        _LazyOwner(events, () {
          factoryCalls++;
          return Object();
        }),
      ]);

      await context.dispose();

      expect(events, <String>['dispose:owner', 'dispose:reader']);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(factoryCalls, 0);
    },
  );

  test('disposing during setup fails and rolls back every module', () async {
    final events = <String>[];

    await expectLater(
      AppContext.create(<Module>[
        _DisposeDuringSetupModule(events),
        _SetupModule('tail', events),
      ]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('during module setup'),
        ),
      ),
    );

    expect(events, <String>[
      'register:self',
      'register:tail',
      'initialize:self',
      'dispose:tail',
      'dispose:self',
    ]);
  });
}

enum _SetupFailurePhase { register, initialize }

final class _SetupModule extends Module {
  const _SetupModule(
    this.name,
    this.events, {
    this.failurePhase,
    this.setupFailure,
    this.disposeFailure,
  });

  final String name;
  final List<String> events;
  final _SetupFailurePhase? failurePhase;
  final Object? setupFailure;
  final Object? disposeFailure;

  @override
  void register(ModuleRegistry registry) {
    events.add('register:$name');
    if (failurePhase == _SetupFailurePhase.register) throw setupFailure!;
  }

  @override
  void initialize(AppContext context) {
    events.add('initialize:$name');
    if (failurePhase == _SetupFailurePhase.initialize) throw setupFailure!;
  }

  @override
  void dispose(AppContext context) {
    events.add('dispose:$name');
    final failure = disposeFailure;
    if (failure != null) throw failure;
  }
}

final class _BlockingModule extends Module {
  const _BlockingModule(
    this.value, {
    required this.gate,
    required this.onStarted,
    required this.onDispose,
    required this.createLazy,
  });

  final Object value;
  final Future<void> gate;
  final void Function() onStarted;
  final void Function() onDispose;
  final Object Function() createLazy;

  @override
  void register(ModuleRegistry registry) {
    _valueKey.provide(registry, value);
    _lazyKey.provideFactory(registry, createLazy);
    registry.bind(const _TestBinding());
  }

  @override
  Future<void> dispose(AppContext context) async {
    expect(context.read(_valueKey), same(value));
    onDispose();
    onStarted();
    await gate;
  }
}

final class _TestBinding implements ModuleBinding {
  const _TestBinding();
}

final class _LazyOwner extends Module {
  _LazyOwner(this.events, this.create);

  final List<String> events;
  final Object Function() create;

  @override
  void register(ModuleRegistry registry) {
    _lazyKey.provideFactory(registry, create);
  }

  @override
  void dispose(AppContext context) {
    events.add('dispose:owner');
  }
}

final class _LazyCleanupReader extends Module {
  _LazyCleanupReader(this.events, this.errors);

  final List<String> events;
  final List<Object> errors;

  @override
  void register(ModuleRegistry registry) {}

  @override
  void dispose(AppContext context) {
    events.add('dispose:reader');
    try {
      context.read(_lazyKey);
    } on Object catch (error) {
      errors.add(error);
    }
  }
}

final class _DisposeDuringSetupModule extends Module {
  _DisposeDuringSetupModule(this.events);

  final List<String> events;

  @override
  void register(ModuleRegistry registry) {
    events.add('register:self');
  }

  @override
  Future<void> initialize(AppContext context) async {
    events.add('initialize:self');
    await context.dispose();
    events.add('initialize:self:after-dispose');
  }

  @override
  void dispose(AppContext context) {
    events.add('dispose:self');
  }
}
