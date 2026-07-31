import 'package:flutter/foundation.dart';

/// Resolves the RPC origin selected by this example application.
Uri? rpcBaseUri({
  bool isWeb = kIsWeb,
  String nativeOrigin = const String.fromEnvironment('ODROE_API_ORIGIN'),
}) {
  if (isWeb) return null;
  if (nativeOrigin.isEmpty) {
    throw StateError('Set ODROE_API_ORIGIN with --dart-define for native RPC.');
  }

  final uri = Uri.tryParse(nativeOrigin);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw FormatException(
      'ODROE_API_ORIGIN must be an absolute HTTP(S) origin.',
      nativeOrigin,
    );
  }
  return uri;
}
