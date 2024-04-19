import 'source.dart';
import 'types.dart';

T get<T>(Readable<T> store) {
  assert(store is CurrentSource<T>);
  return (store as CurrentSource<T>).source;
}
