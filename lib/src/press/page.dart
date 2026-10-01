import '../document/document.dart';
import '../mdc/ast.dart';
import '../mdc/html.dart';
import '../mdc/outline.dart';

/// One immutable page in a Press content collection.
final class PressPage {
  /// Creates a parsed content page.
  PressPage({
    required Iterable<String> slug,
    required this.location,
    required this.title,
    required this.content,
    required this.sourcePath,
    this.description,
    this.order = 0,
    this.draft = false,
    this.language,
  }) : slug = List<String>.unmodifiable(slug) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be empty.');
    }
    if (!location.hasAbsolutePath ||
        location.hasScheme ||
        location.hasAuthority ||
        location.hasQuery ||
        location.hasFragment) {
      throw ArgumentError.value(
        location,
        'location',
        'Must be an absolute local path without query or fragment.',
      );
    }
    for (final segment in this.slug) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains(r'\')) {
        throw ArgumentError.value(slug, 'slug', 'Contains an invalid segment.');
      }
    }
  }

  /// Path segments relative to the collection mount.
  final List<String> slug;

  /// Public page location.
  final Uri location;

  /// Page title from frontmatter.
  final String title;

  /// Optional search and navigation description.
  final String? description;

  /// Navigation order.
  final int order;

  /// Whether this page is excluded from normal collections.
  final bool draft;

  /// Optional document language.
  final String? language;

  /// Parsed renderer-neutral MDC content.
  final MdcDocument content;

  /// Complete immutable frontmatter, including application-owned fields.
  Map<String, Object?> get frontmatter => content.frontmatter;

  /// Source path relative to the content root.
  final String sourcePath;

  /// Hierarchical heading outline.
  List<MdcOutlineEntry> get outline => content.outline;

  /// Renders this page as a semantic route document.
  RouteDocument toDocument({MdcHtmlRenderer? renderer, Uri? canonicalOrigin}) {
    if (canonicalOrigin != null &&
        (!canonicalOrigin.hasScheme ||
            (canonicalOrigin.scheme != 'http' &&
                canonicalOrigin.scheme != 'https') ||
            canonicalOrigin.host.isEmpty ||
            canonicalOrigin.userInfo.isNotEmpty ||
            (canonicalOrigin.path.isNotEmpty && canonicalOrigin.path != '/') ||
            canonicalOrigin.hasQuery ||
            canonicalOrigin.hasFragment)) {
      throw ArgumentError.value(
        canonicalOrigin,
        'canonicalOrigin',
        'Must be an absolute HTTP(S) origin without path, query, or fragment.',
      );
    }
    return RouteDocument(
      language: language,
      title: title,
      description: description,
      canonical: canonicalOrigin?.resolveUri(location).toString(),
      body: (renderer ?? MdcHtmlRenderer()).render(content),
    );
  }
}
