// ignore_for_file: public_member_api_docs

import 'dart:async';

/// Cancellation raised by Query without treating it as a request failure.
final class QueryCancelledException implements Exception {
  const QueryCancelledException({this.silent = false, this.revert = true});

  /// Suppresses error-state notifications when true.
  final bool silent;

  /// Restores the state captured immediately before the fetch when true.
  final bool revert;

  @override
  String toString() =>
      'QueryCancelledException(silent: $silent, revert: $revert)';
}

/// A transport-neutral cancellation signal supplied to query functions.
final class QueryCancelToken {
  QueryCancelToken._();

  final Completer<QueryCancelledException> _cancelled =
      Completer<QueryCancelledException>();
  bool _consumed = false;
  QueryCancelledException? _reason;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes with the cancellation reason.
  Future<QueryCancelledException> get whenCancelled {
    _consumed = true;
    return _cancelled.future;
  }

  /// Records that the query function connected this token to its transport.
  void markConsumed() {
    _consumed = true;
  }

  /// Throws immediately when cancellation has already been requested.
  void throwIfCancelled() {
    _consumed = true;
    if (isCancelled) throw _reason!;
  }
}

final class QueryCancellationController {
  QueryCancellationController() : token = QueryCancelToken._();

  final QueryCancelToken token;

  bool get consumed => token._consumed;

  Future<QueryCancelledException> get whenCancelled => token._cancelled.future;

  void cancel({bool silent = false, bool revert = true}) {
    if (!token._cancelled.isCompleted) {
      final reason = QueryCancelledException(silent: silent, revert: revert);
      token._reason = reason;
      token._cancelled.complete(reason);
    }
  }
}
