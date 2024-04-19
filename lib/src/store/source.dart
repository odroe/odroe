import 'types.dart';

abstract interface class CurrentSource<T> {
  T get source;
}

mixin StoreSource<T> {
  Readable<T> get store;

  T get source {
    assert(store is CurrentSource<T>);
    return (store as CurrentSource<T>).source;
  }
}
