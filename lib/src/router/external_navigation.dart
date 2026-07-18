// ignore_for_file: public_member_api_docs

import 'external_navigation_stub.dart'
    if (dart.library.html) 'external_navigation_web.dart'
    as platform;

bool navigateExternal(Uri location, {required bool replace}) =>
    platform.navigateExternal(location, replace: replace);
