import 'package:odroe/odroe.dart';
import 'package:odroe/store.dart';

/// Create a rune linking a store.
///
/// ```dart
/// final counterStore = writeable(0);
///
/// Widget example() => setup(() {
///   final count = $store(counterStore);
///
///   void plusOne() => counterStore.update((value) => value + 1);
///
///   return TextButton(
///     onPressed: plusOne,
///     child: Text('Count: $count'),
///   );
/// });
/// ```
///
/// [$store] Returns the value of the current Store, and notifies the widget to
/// rebuild when the value of the Store changes.
T $store<T>(Readable<T> store) {
  final ref = $state(get(store));

  $effect(
    () => store.subscribe((value) => ref.set(value)),
  );

  return ref.get();
}
