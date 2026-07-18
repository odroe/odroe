// ignore_for_file: public_member_api_docs

import 'handoff_browser_stub.dart'
    if (dart.library.html) 'handoff_browser_web.dart'
    as platform;

Map<String, Object?>? readBrowserHandoff() => platform.readBrowserHandoff();

Stream<Map<String, Object?>> browserHandoffFrames() =>
    platform.browserHandoffFrames();

void hideBrowserDocument() => platform.hideBrowserDocument();
