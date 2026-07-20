import 'package:web/web.dart';

/// Navigates the browser to [location].
bool navigateExternal(Uri location, {required bool replace}) {
  if (replace) {
    window.location.replace(location.toString());
  } else {
    window.location.assign(location.toString());
  }
  return true;
}
