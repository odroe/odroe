import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('globalThis.document')
external web.Document? get _document;

// Fetch uses the document base in a page, or the location in a worker.
// Uri.base alone misses <base href> in pages. Send the resolved URL itself so
// a later navigation or <base> change cannot retarget a prepared read.
/// @nodoc
Uri resolveRpcEndpoint(Uri endpoint) => endpoint.hasScheme
    ? endpoint
    : Uri.parse(_document?.baseURI ?? Uri.base.toString()).resolveUri(endpoint);
