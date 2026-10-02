/// Parsed response preferences for Odroe's HTML and JSON representations.
final class AcceptPreferences {
  /// Parses one combined HTTP `Accept` header value.
  factory AcceptPreferences.parse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const AcceptPreferences._(html: 1, json: 1);
    }
    final ranges = <_MediaRange>[
      for (final item in value.split(',')) ?_MediaRange.tryParse(item),
    ];
    return AcceptPreferences._(
      html: _quality(ranges, 'text', 'html'),
      json: _quality(ranges, 'application', 'json'),
    );
  }

  const AcceptPreferences._({required this.html, required this.json});

  /// Effective quality for `text/html`.
  final double html;

  /// Effective quality for `application/json`.
  final double json;

  /// Whether JSON is explicitly preferred over HTML.
  bool get prefersJson => json > html;

  /// Whether HTML is acceptable and JSON is not preferred over it.
  bool get acceptsHtml => html > 0 && !prefersJson;
}

final class _MediaRange {
  const _MediaRange(this.type, this.subtype, this.quality);

  static _MediaRange? tryParse(String value) {
    final parts = value.split(';');
    final media = parts.first.trim().toLowerCase().split('/');
    if (media.length != 2 ||
        media.first.isEmpty ||
        media.last.isEmpty ||
        (media.first == '*' && media.last != '*')) {
      return null;
    }
    var quality = 1.0;
    for (final parameter in parts.skip(1)) {
      final separator = parameter.indexOf('=');
      if (separator < 0 ||
          parameter.substring(0, separator).trim().toLowerCase() != 'q') {
        continue;
      }
      final parsed = double.tryParse(parameter.substring(separator + 1).trim());
      quality = parsed != null && parsed >= 0 && parsed <= 1 ? parsed : 0;
    }
    return _MediaRange(media.first, media.last, quality);
  }

  final String type;
  final String subtype;
  final double quality;

  int specificity(String candidateType, String candidateSubtype) {
    if (type != '*' && type != candidateType) return -1;
    if (subtype != '*' && subtype != candidateSubtype) return -1;
    return type == '*' ? 0 : (subtype == '*' ? 1 : 2);
  }
}

double _quality(List<_MediaRange> ranges, String type, String subtype) {
  var specificity = -1;
  var quality = 0.0;
  for (final range in ranges) {
    final candidate = range.specificity(type, subtype);
    if (candidate < 0) continue;
    if (candidate > specificity) {
      specificity = candidate;
      quality = range.quality;
    } else if (candidate == specificity && range.quality > quality) {
      quality = range.quality;
    }
  }
  return quality;
}
