import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oref/oref.dart';

class WriteReadBenchmark extends BenchmarkBase {
  WriteReadBenchmark({super.emitter}) : super('write/read');

  late int counter;
  late Ref reference;

  @override
  void run() {
    reference.value = counter++;
    reference.value;
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
