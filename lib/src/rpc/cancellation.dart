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
Stream<T> stopOnRpcCancellation<T>(Stream<T> source, Future<void>? cancelled) =>
    cancelled == null
    ? source
    : Stream<T>.eventTransformed(
        source,
        (sink) => _RpcCancellationSink<T>(sink, cancelled),
      );

final class _RpcCancellationSink<T> implements EventSink<T> {
  _RpcCancellationSink(this._output, Future<void> cancelled) {
    unawaited(
      cancelled.then<void>(
        (_) => _cancel(),
        onError: (Object _, StackTrace _) => _cancel(),
      ),
    );
  }

  EventSink<T>? _output;

  @override
  void add(T data) => _output?.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _output?.addError(error, stackTrace);

  @override
  void close() {
    final output = _output;
    if (output == null) return;
    _output = null;
    output.close();
  }

  void _cancel() {
    final output = _output;
    if (output == null) return;
    _output = null;
    output
      ..addError(const RpcCancelledException())
      ..close();
  }
}
