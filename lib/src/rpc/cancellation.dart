import 'dart:async';

/// Indicates that the caller cancelled an RPC request.
final class RpcCancelledException implements Exception {
  /// Creates an RPC cancellation exception.
  const RpcCancelledException();

  @override
  String toString() => 'RpcCancelledException';
}

/// Runs one RPC phase unless [cancelled] completes first.
Future<T> runUntilRpcCancelled<T>(
  FutureOr<T> Function() operation,
  Future<void>? cancelled,
) {
  if (cancelled == null) return Future<T>.sync(operation);

  final result = Completer<T>();

  void cancel() {
    if (!result.isCompleted) {
      result.completeError(const RpcCancelledException());
    }
  }

  unawaited(
    cancelled.then<void>(
      (_) => cancel(),
      onError: (Object _, StackTrace _) => cancel(),
    ),
  );
  scheduleMicrotask(() {
    if (result.isCompleted) return;
    unawaited(
      Future<T>.sync(operation).then<void>(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );
  });

  return result.future;
}

/// Stops [source] with [RpcCancelledException] when [cancelled] completes.
Stream<T> stopOnRpcCancellation<T>(Stream<T> source, Future<void>? cancelled) {
  if (cancelled == null) return source;

  late final StreamController<T> output;
  StreamSubscription<T>? input;
  var stopped = false;

  void stop() {
    if (stopped) return;
    final subscription = input;
    input = null;
    stopped = true;
    unawaited(_cancelSubscription(subscription));
    output.addError(const RpcCancelledException());
    unawaited(output.close());
  }

  void listen() {
    if (stopped) return;
    try {
      final subscription = source.listen(
        (data) {
          if (!stopped) output.add(data);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!stopped) output.addError(error, stackTrace);
        },
        onDone: () {
          if (stopped) return;
          input = null;
          stopped = true;
          unawaited(output.close());
        },
        cancelOnError: false,
      );
      input = subscription;
      if (stopped) unawaited(_cancelSubscription(subscription));
    } on Object catch (error, stackTrace) {
      if (!stopped) {
        stopped = true;
        output.addError(error, stackTrace);
        unawaited(output.close());
      }
    }
  }

  output = StreamController<T>(
    sync: true,
    onListen: listen,
    onPause: () => input?.pause(),
    onResume: () => input?.resume(),
    onCancel: () {
      final subscription = input;
      input = null;
      stopped = true;
      return _cancelSubscription(subscription);
    },
  );
  unawaited(
    cancelled.then<void>(
      (_) => stop(),
      onError: (Object _, StackTrace _) => stop(),
    ),
  );
  return output.stream;
}

Future<void> _cancelSubscription<T>(StreamSubscription<T>? subscription) async {
  try {
    await subscription?.cancel();
  } on Object {
    // Cancellation cleanup must not escape as an unrelated asynchronous error.
  }
}
