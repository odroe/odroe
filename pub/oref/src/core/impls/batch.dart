import '../types/private.dart' as private;
import 'flags.dart';

int batchDepth = 0;
private.Subscriber? evalSubscriber;

void startBatch() => batchDepth++;

void batch(private.Subscriber subscriber) {
  subscriber.flags |= Flags.dirty;
  if (evalSubscriber == null) {
    subscriber.children.clear();
  } else if (!subscriber.children.contains(evalSubscriber)) {
    subscriber.children.add(evalSubscriber!);

    // Merge children of evalSubscriber into subscriber.
    subscriber.children.addAll(evalSubscriber!.children);
    evalSubscriber!.children.clear();
  }

  evalSubscriber = subscriber;
}

void endBatch() {
  batchDepth--;
  if (batchDepth > 0) return;

  Object? error;
  while (evalSubscriber != null) {
    // 1st pass: clear notified flag.
    _cleanNotifiedFlag(evalSubscriber!);

    final subscriber = evalSubscriber!;
    evalSubscriber = null;

    // 2nd pass: run effects.
    _runEffects(subscriber, (e) => error ??= e);
  }

  if (error != null) {
    throw error!;
  }
}

void _runEffects(
  private.Subscriber subscriber,
  void Function(Object) setError,
) {
  final children = List.from(subscriber.children);
  subscriber.children.clear();

  subscriber.flags &= ~Flags.notified;
  if ((subscriber.flags & Flags.active) != 0) {
    try {
      // active is effect-only flag.
      (subscriber as private.Effect).trigger();
    } catch (e) {
      setError(e);
    }
  }

  for (final child in children) {
    _runEffects(child, setError);
  }
}

void _cleanNotifiedFlag(private.Subscriber subscriber) {
  if ((subscriber.flags & Flags.active) == 0) {
    subscriber.flags &= ~Flags.notified;
  }

  if (subscriber.children.isNotEmpty) {
    for (final child in subscriber.children) {
      _cleanNotifiedFlag(child);
    }
  }
}
