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
  final serverRequest = ServerRequest(
    method: HttpMethod.parse(request.method),
    uri: Uri.parse(request.url),
    headers: _readHeaders(request.headers),
    body: requestBody == null ? null : _readBody(requestBody),
    cancelled: _cancelled(request.signal),
  );
  final response = await handler(serverRequest, invocation);
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
    }

    final headers = web.Headers();
    for (final entry in response.headers.entries) {
      for (final value in entry.value) {
        headers.append(entry.key, value);
      }
    }
    final result = web.Response(
      omitBody ? null : _ResponseBodySource(response.body).stream,
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

Stream<List<int>> _readBody(web.ReadableStream body) async* {
  final reader = web.ReadableStreamDefaultReader(body);
  var done = false;
  try {
    while (true) {
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
      if (!done) await reader.cancel().toDart;
    } finally {
      reader.releaseLock();
    }
  }
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
  _ResponseBodySource(Stream<List<int>> body)
    : _iterator = StreamIterator<List<int>>(body);

  final StreamIterator<List<int>> _iterator;
  bool _closed = false;

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
        _closed = true;
        controller.close();
        return null;
      }
      final chunk = _iterator.current;
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      controller.enqueue(bytes.toJS);
      return null;
    } on Object catch (error, stackTrace) {
      _closed = true;
      try {
        await _iterator.cancel();
      } on Object {
        // Preserve the stream's primary error.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<JSAny?> _cancel() async {
    if (_closed) return null;
    _closed = true;
    await _iterator.cancel();
    return null;
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
