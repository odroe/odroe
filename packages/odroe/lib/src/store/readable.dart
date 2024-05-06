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

/// Creates a store whose value cannot be set from 'outside', the first
/// argument is the store's initial value, and the second argument to
/// [readable] is the same as the second argument to [writable].
///
/// ```dart
/// final time = readable(new DateTime(), (actions) {
///   actions.set(new DateTime());
///
///   final timer = Timer.periodic(const Duration(seconds: 1), (_) {
///     actions.set(new DateTime());
///   });
///
///   return timer.cancel;
/// });
/// ```
Readable<T> readable<T>(T value, [StartStopNotifier<T>? start]) =>
    _Readable(writeable(value, start));
