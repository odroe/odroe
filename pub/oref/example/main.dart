import 'package:oref/oref.dart';

void main() {
  final count = ref(0);
  final double = derived(() => count.value * 2);
  final runner = effect(() {
    print('count: ${count.value}, double: ${double.value}');
  }, onStop: () {
    print('effect stopped');
  });

  count.value = 10; // prints 'count: 10, double: 20'
  runner.effect.stop(); // prints 'effect stopped'

  count.value = 20; // nothing

  // Has stopped, but can be manually executed through runner
  runner(); // Call once, prints 'count: 20, double: 40'

  count.value = 30; // nothing
}
