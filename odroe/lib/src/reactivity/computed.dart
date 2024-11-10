import 'corss_link.dart';
import 'debugger.dart';
import 'ref.dart';
import 'subscriber.dart';

abstract interface class Computed<T> implements Ref<T> {}

final class ComputedImpl<T> implements Computed<T>, Subscriber {
  @override
  T get value => throw UnimplementedError();

  @override
  CrossLink? depsHead;

  @override
  CrossLink? depsTail;

  @override
  int flags;

  @override
  Subscriber? next;

  @override
  void notify() {
    // TODO: implement notify
  }

  @override
  void Function(DebuggerEvent event)? onTrack;

  @override
  void Function(DebuggerEvent event)? onTrigger;
}

void refreshComputed(ComputedImpl computed) {}
