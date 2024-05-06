import 'source.dart';
import 'types.dart';

/// Returns the current value of the store.
T get<T>(Readable<T> store) {
  assert(store is CurrentSource<T>);
  return (store as CurrentSource<T>).source;
}
