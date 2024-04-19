import 'package:odroe/src/store/writeable.dart';

import 'source.dart';
import 'types.dart';

class _Readable<T>
    with StoreSource<T>
    implements Readable<T>, CurrentSource<T> {
  const _Readable(this.store);

  @override
  final Writeable<T> store;

  @override
  Unsubscriber subscribe(Subscriber<T> subscriber) =>
      store.subscribe(subscriber);

  @override
  T get source {
    assert(store is CurrentSource<T>);
    return (store as CurrentSource<T>).source;
  }
}

Readable<T> readable<T>(T value, [StartStopNotifier<T>? start]) =>
    _Readable(writeable(value, start));
