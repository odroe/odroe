/// Validates and canonicalizes an RPC function namespace.
String normalizeFunctionPath(String value) {
  final normalized = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  final uri = Uri.tryParse(normalized);
  final segments = uri?.pathSegments;
  if (uri == null ||
      normalized.length < 2 ||
      !normalized.startsWith('/') ||
      uri.path != normalized ||
      segments == null ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(
      value,
      'functionPath',
      'Must be a non-root absolute path without query or fragment.',
    );
  }
  return normalized;
}
