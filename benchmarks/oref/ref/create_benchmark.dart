import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:oref/oref.dart';

class CreateBenchmark extends BenchmarkBase {
  const CreateBenchmark({super.emitter}) : super('create');

  @override
  void run() {
    ref(100);
  }
}
