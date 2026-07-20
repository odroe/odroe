import 'browser_stub.dart'
    if (dart.library.html) 'browser_web.dart'
    as platform;

/// Reads and removes the embedded initial handoff payload.
Map<String, Object?>? readBrowserHandoff() => platform.readBrowserHandoff();

/// Streams handoff frames appended by the server.
Stream<Map<String, Object?>> browserHandoffFrames() =>
    platform.browserHandoffFrames();

/// Hides the semantic HTML after Flutter paints its first frame.
void hideBrowserDocument() => platform.hideBrowserDocument();
