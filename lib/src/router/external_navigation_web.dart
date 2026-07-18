// ignore_for_file: deprecated_member_use, public_member_api_docs

import 'dart:html';

bool navigateExternal(Uri location, {required bool replace}) {
  if (replace) {
    window.location.replace(location.toString());
  } else {
    window.location.assign(location.toString());
  }
  return true;
}
