/// Validates and canonicalizes an RPC function namespace.
String normalizeFunctionPath(String value, {bool allowRelative = false}) {
  final normalized = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  final uri = Uri.tryParse(normalized);
  final segments = uri?.pathSegments;
  if (uri == null ||
      normalized.isEmpty ||
      normalized == '/' ||
      (!allowRelative && !normalized.startsWith('/')) ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != normalized ||
      segments == null ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(
      value,
      'functionPath',
      allowRelative
          ? 'Must be a non-root path without scheme, query, or fragment.'
          : 'Must be a non-root absolute path without query or fragment.',
    );
  }
  return normalized;
}
