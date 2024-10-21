import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oref/oref.dart';

class CreateBenchmark extends BenchmarkBase {
  const CreateBenchmark({super.emitter}) : super('create');

  @override
  void run() {
    derived(() => 100);
  }
}

class WriteRefDontReadDerivedWitoutEffect extends BenchmarkBase {
  WriteRefDontReadDerivedWitoutEffect({super.emitter})
      : super("write ref, don't read derived (without effect)");

  late Ref v;
  late int i;

  @override
  void run() {
    v.value = i++;
  }

  @override
  setup() {
    i = 0;
    v = ref(100);
    derived(() => v.value * 2);
  }
}

class WriteRefDontReadDerivedWithEffect extends BenchmarkBase {
  WriteRefDontReadDerivedWithEffect({super.emitter})
      : super('write ref, don\'t read derived (with effect)');

  late int i;
  late Ref v;
  late EffectRunner e;

  @override
  void run() {
    v.value = i++;
  }

  @override
  setup() {
    i = 0;
    v = ref(100);

    final d = derived(() => v.value * 2);
    e = effect(() => d.value);
  }

  @override
  teardown() {
    e.effect.stop();
  }
}

class WriteRefReadDerivedWithoutEffect extends BenchmarkBase {
  WriteRefReadDerivedWithoutEffect({super.emitter})
      : super("write ref, read derived (without effect)");

  late int i;
  late Ref v;
  late Derived d;

  @override
  void run() {
    v.value = i++;
    d.value;
  }

  @override
  setup() {
    i = 0;
    v = ref(100);
    d = derived(() => v.value * 2);
  }
}

class WriteRefReadDerivedWithEffect extends BenchmarkBase {
  WriteRefReadDerivedWithEffect({super.emitter})
      : super('write ref, read derived (with effect)');

  late int i;
  late Ref v;
  late Derived d;
  late EffectRunner e;

  @override
  void run() {
    v.value = i++;
    d.value;
  }

  @override
  setup() {
    i = 0;
    v = ref(100);
    d = derived(() => v.value * 2);
    e = effect(() => d.value);
  }

  @override
  teardown() {
    e.effect.stop();
  }
}
