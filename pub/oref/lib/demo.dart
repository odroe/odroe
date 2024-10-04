import 'oref.dart';

main() {
  final a = ref(0);
  final b = derived((_) => a.value * 2);

  final c = effect(() {
    print('b: ${b.value}');
  });

  print((a as dynamic).dep.subs);

  // a.value = 1;
  // a.value = 2;
}
