import 'package:benchmark_harness/benchmark_harness.dart';

import 'oref/ref/create_benchmark.dart' as ref;
import 'oref/ref/write_benchmark.dart' as ref;
import 'oref/ref/read_benchmark.dart' as ref;
import 'oref/ref/write_read_benchmark.dart' as ref;

import 'oref/derived.dart' as derived;

class Emitter implements ScoreEmitter {
  const Emitter(this.scope);
  final String scope;

  @override
  void emit(String name, double value) {
    print('${scope} - ${name}: ${value}us');
  }
}

main() {
  const refEmitter = const Emitter('oref:ref');
  ref.CreateBenchmark(emitter: refEmitter).report();
  ref.WriteBenchmark(emitter: refEmitter).report();
  ref.ReadBenchmark(emitter: refEmitter).report();
  ref.WriteReadBenchmark(emitter: refEmitter).report();

  const derivedEmitter = Emitter('oref:derived');
  derived.CreateBenchmark(emitter: derivedEmitter).report();
  derived.WriteRefDontReadDerivedWitoutEffect(emitter: derivedEmitter).report();
  derived.WriteRefDontReadDerivedWithEffect(emitter: derivedEmitter).report();
  derived.WriteRefReadDerivedWithoutEffect(emitter: derivedEmitter).report();
  derived.WriteRefReadDerivedWithEffect(emitter: derivedEmitter).report();
}
