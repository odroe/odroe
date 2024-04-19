import 'source.dart';
import 'types.dart';

class _Readonly<T>
    with StoreSource<T>
    implements Readable<T>, CurrentSource<T> {
  const _Readonly(this.store);

  @override
  final Readable<T> store;

  @override
  Unsubscriber subscribe(Subscriber<T> subscriber) =>
      store.subscribe(subscriber);
}

Readable<T> readonly<T>(Readable<T> store) => _Readonly(store);
