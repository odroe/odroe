import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oref/oref.dart';

class WriteBenchmark extends BenchmarkBase {
  WriteBenchmark({super.emitter}) : super('write');

  late int counter;
  late Ref reference;

  @override
  void run() {
    reference.value = counter++;
  }

  @override
  setup() {
    counter = 0;
    reference = ref(100);
  }

  @override
  teardown() {
    counter = 0;
  }
}
