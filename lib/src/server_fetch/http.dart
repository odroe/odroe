import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../server/http.dart';
import '../server/invocation.dart';

/// Converts one Fetch invocation to Odroe HTTP values and back.
Future<web.Response> handleFetchInvocation(
  ServerInvocationHandler handler,
  web.Request request,
  ServerInvocation invocation,
) async {
  final requestBody = request.body;
  final requestBodySource = requestBody == null
      ? null
      : _RequestBodySource(requestBody);
  late final HttpMethod method;
  try {
    method = HttpMethod.parse(request.method);
  } on FormatException {
    await _cancelRequestBody(requestBodySource);
    return web.Response(
      null,
      web.ResponseInit(status: 501, statusText: 'Not Implemented'),
    );
  }
  final serverRequest = ServerRequest(
    method: method,
    uri: Uri.parse(request.url),
    headers: _readHeaders(request.headers),
    body: requestBodySource?.stream,
    cancelled: _cancelled(request.signal),
  );
  late final ServerResponse response;
  try {
    response = await handler(serverRequest, invocation);
  } on Object catch (error, stackTrace) {
    await _cancelRequestBody(requestBodySource);
    Error.throwWithStackTrace(error, stackTrace);
  }
  final omitBody =
      serverRequest.method == HttpMethod.head ||
      response.status < 200 ||
      response.status == 204 ||
      response.status == 205 ||
      response.status == 304;
  var bodyHandled = false;
  try {
    if (omitBody) {
      bodyHandled = true;
      await _cancelBody(response.body);
      await _cancelRequestBody(requestBodySource);
    }

    final headers = web.Headers();
    for (final entry in response.headers.entries) {
      for (final value in entry.value) {
        headers.append(entry.key, value);
      }
    }
    final body = omitBody
        ? null
        : _ResponseBodySource(
            response.body,
            onDone: () => _cancelRequestBody(requestBodySource),
          ).stream;
    final result = web.Response(
      body,
      web.ResponseInit(
        status: response.status,
        statusText: response.reason ?? '',
        headers: headers,
      ),
    );
    bodyHandled = true;
    return result;
  } on Object catch (error, stackTrace) {
    if (!bodyHandled) {
      try {
        await _cancelBody(response.body);
      } on Object {
        // Preserve the response-conversion failure.
      }
    }
    await _cancelRequestBody(requestBodySource);
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Headers _readHeaders(web.Headers source) {
  final headers = Headers();
  _FetchHeaders(source).forEach(
    ((JSString value, JSString name) {
      headers.append(name.toDart, value.toDart);
    }).toJS,
  );
  return headers;
}

Future<void> _cancelled(web.AbortSignal signal) {
  if (signal.aborted) return Future<void>.value();
  final cancelled = Completer<void>();
  signal.addEventListener(
    'abort',
    ((web.Event _) {
      if (!cancelled.isCompleted) cancelled.complete();
    }).toJS,
    web.AddEventListenerOptions(once: true),
  );
  return cancelled.future;
}

Future<void> _cancelBody(Stream<List<int>> body) async {
  final subscription = body.listen(null);
  await subscription.cancel();
}

final class _ResponseBodySource {
  _ResponseBodySource(
    Stream<List<int>> body, {
    required Future<void> Function() onDone,
  }) : _iterator = StreamIterator<List<int>>(body),
       _onDone = onDone;

  final StreamIterator<List<int>> _iterator;
  final Future<void> Function() _onDone;
  bool _closed = false;
  bool _cancelled = false;
  Future<void>? _closing;

  web.ReadableStream get stream => web.ReadableStream(
    _UnderlyingSource(
      pull: ((web.ReadableStreamDefaultController controller) {
        return _pull(controller).toJS;
      }).toJS,
      cancel: ((JSAny? _) => _cancel().toJS).toJS,
    ),
  );

  Future<JSAny?> _pull(web.ReadableStreamDefaultController controller) async {
    if (_closed) return null;
    try {
      if (!await _iterator.moveNext()) {
        await _close(cancelIterator: false);
        controller.close();
        return null;
      }
      final chunk = _iterator.current;
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      controller.enqueue(bytes.toJS);
      return null;
    } on Object catch (error, stackTrace) {
      try {
        await _close(cancelIterator: true);
      } on Object {
        // Preserve the stream's primary error.
      }
      if (_cancelled) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<JSAny?> _cancel() async {
    _cancelled = true;
    await _close(cancelIterator: true);
    return null;
  }

  Future<void> _close({required bool cancelIterator}) {
    _closed = true;
    return _closing ??= _closeOnce(cancelIterator: cancelIterator);
  }

  Future<void> _closeOnce({required bool cancelIterator}) async {
    try {
      if (cancelIterator) await _iterator.cancel();
    } finally {
      try {
        await _onDone();
      } on Object {
        // Request-body cleanup must not replace the response outcome.
      }
    }
  }
}

final class _RequestBodySource {
  _RequestBodySource(this._body);

  final web.ReadableStream _body;
  web.ReadableStreamDefaultReader? _reader;
  var _opened = false;
  var _closed = false;
  Future<void>? _cancelling;

  Stream<List<int>> get stream => _read();

  Stream<List<int>> _read() async* {
    if (_opened) throw StateError('Fetch request body is single-use.');
    _opened = true;
    if (_closed) return;
    final reader = web.ReadableStreamDefaultReader(_body);
    _reader = reader;
    var done = false;
    try {
      while (!_closed) {
        final result = await reader.read().toDart;
        if (result.done) {
          done = true;
          break;
        }
        final value = result.value;
        if (value == null) {
          throw StateError('Fetch body returned an empty chunk.');
        }
        yield (value as JSUint8Array).toDart;
      }
    } finally {
      try {
        if (!done && !_closed) await reader.cancel().toDart;
      } finally {
        _closed = true;
        _release(reader);
      }
    }
  }

  Future<void> cancel() => _cancelling ??= _cancel();

  Future<void> _cancel() async {
    if (_closed) return;
    _closed = true;
    final reader = _reader;
    if (reader == null) {
      await _body.cancel().toDart;
      return;
    }
    try {
      await reader.cancel().toDart;
    } finally {
      _release(reader);
    }
  }

  void _release(web.ReadableStreamDefaultReader reader) {
    if (_reader == null) return;
    _reader = null;
    reader.releaseLock();
  }
}

Future<void> _cancelRequestBody(_RequestBodySource? source) async {
  if (source == null) return;
  try {
    await source.cancel();
  } on Object {
    // Cleanup must not replace the request or response outcome.
  }
}

extension type _FetchHeaders(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}

extension type _UnderlyingSource._(JSObject _) implements JSObject {
  external factory _UnderlyingSource({
    required JSFunction pull,
    required JSFunction cancel,
  });
}
