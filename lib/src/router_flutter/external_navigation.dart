import 'external_navigation_stub.dart'
    if (dart.library.html) 'external_navigation_web.dart'
    as platform;

/// Opens [location] in the host platform when it is outside the app router.
bool navigateExternal(Uri location, {required bool replace}) =>
    platform.navigateExternal(location, replace: replace);
