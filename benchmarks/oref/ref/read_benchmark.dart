import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oref/oref.dart';

class ReadBenchmark extends BenchmarkBase {
  ReadBenchmark({super.emitter}) : super('read');

  late Ref reference;

  @override
  void run() {
    reference.value;
  }

  @override
  setup() {
    reference = ref(100);
  }
}
