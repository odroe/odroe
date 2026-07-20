/// Returns no handoff outside a browser.
Map<String, Object?>? readBrowserHandoff() => null;

/// Returns no streamed frames outside a browser.
Stream<Map<String, Object?>> browserHandoffFrames() =>
    const Stream<Map<String, Object?>>.empty();

/// Does nothing outside a browser.
void hideBrowserDocument() {}
