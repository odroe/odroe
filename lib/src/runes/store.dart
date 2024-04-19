import 'package:odroe/odroe.dart';
import 'package:odroe/store.dart';

T $store<T>(Readable<T> store) {
  final ref = $state(get(store));

  $effect(
    () => store.subscribe((value) => ref.set(value)),
  );

  return ref.get();
}
