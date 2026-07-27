/// Controls which links and images may produce navigable destinations.
final class MdcUriPolicy {
  /// Creates an MDC URI policy.
  const MdcUriPolicy({
    this.linkSchemes = const <String>{'http', 'https', 'mailto', 'tel'},
    this.imageSchemes = const <String>{'http', 'https'},
    this.allowRelative = true,
    this.allowProtocolRelative = false,
  });

  /// Lowercase URI schemes accepted by link destinations.
  final Set<String> linkSchemes;

  /// Lowercase URI schemes accepted by image sources.
  final Set<String> imageSchemes;

  /// Whether paths, fragments, and query-only references are accepted.
  final bool allowRelative;

  /// Whether network-path references such as `//cdn.example/image.png` work.
  final bool allowProtocolRelative;

  /// Returns a safe link destination, or `null` when [value] is rejected.
  String? link(String value) => _sanitize(value, linkSchemes);

  /// Returns a safe image source, or `null` when [value] is rejected.
  String? image(String value) => _sanitize(value, imageSchemes);

  String? _sanitize(String value, Set<String> schemes) {
    final candidate = value.trim();
    if (candidate.isEmpty || _hasControlCharacter(candidate)) return null;
    if (candidate.contains(r'\')) return null;
    if (candidate.startsWith('//')) {
      return allowProtocolRelative ? candidate : null;
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (!uri.hasScheme) return allowRelative ? candidate : null;
    return schemes.contains(uri.scheme.toLowerCase()) ? candidate : null;
  }
}

bool _hasControlCharacter(String value) {
  for (final unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return true;
  }
  return false;
}
