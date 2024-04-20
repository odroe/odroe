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

/// This simple helper function makes a store readonly. You can still subscribe
/// to the changes from the original one using this new [readable] store.
///
/// ```dart
/// final writeableStore = writeable(1);
/// final readableStore = readonly(writeable);
///
/// readableStore.subscribe(print);
///
/// writeable.set(2); // print 2
/// ```
Readable<T> readonly<T>(Readable<T> store) => _Readonly(store);
