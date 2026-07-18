import 'node.dart';

/// One HTML metadata declaration.
final class DocumentMeta {
  /// Creates a named metadata declaration.
  const DocumentMeta.name(this.key, this.content)
    : attribute = 'name',
      charset = null;

  /// Creates a property metadata declaration, such as Open Graph data.
  const DocumentMeta.property(this.key, this.content)
    : attribute = 'property',
      charset = null;

  /// Creates an HTTP-equivalent metadata declaration.
  const DocumentMeta.httpEquiv(this.key, this.content)
    : attribute = 'http-equiv',
      charset = null;

  /// Creates a character encoding declaration.
  const DocumentMeta.charset(this.charset)
    : attribute = null,
      key = null,
      content = null;

  /// The identifying HTML attribute.
  final String? attribute;

  /// The name, property, or HTTP header key.
  final String? key;

  /// The metadata content.
  final String? content;

  /// The declared character encoding.
  final String? charset;

  /// Stable merge identity for this metadata kind and key.
  String get identity => charset == null ? '$attribute:$key' : 'charset';
}

/// One link declaration in the document head.
final class DocumentLink {
  /// Creates a link declaration.
  const DocumentLink({
    required this.rel,
    required this.href,
    this.hreflang,
    this.media,
    this.type,
    this.as,
    this.crossorigin,
  });

  /// The link relationship.
  final String rel;

  /// The linked location.
  final String href;

  /// The alternate language, when relevant.
  final String? hreflang;

  /// The target media query.
  final String? media;

  /// The linked resource MIME type.
  final String? type;

  /// The preload destination.
  final String? as;

  /// The cross-origin mode.
  final String? crossorigin;

  /// Stable merge identity for this link relationship and target.
  String get identity => rel == 'canonical'
      ? rel
      : '$rel\u0000$href\u0000${hreflang ?? ''}\u0000${media ?? ''}'
            '\u0000${type ?? ''}\u0000${as ?? ''}';
}

/// Route-owned semantic HTML and head information.
///
/// Parent and child route documents are merged in match order. The deepest
/// title and duplicate metadata win. A parent's [body] may contain an
/// [HtmlOutlet] where its matched child's body is inserted.
final class RouteDocument {
  /// Creates one route document fragment.
  const RouteDocument({
    this.language,
    this.baseHref,
    this.title,
    this.description,
    this.canonical,
    this.meta = const <DocumentMeta>[],
    this.links = const <DocumentLink>[],
    this.jsonLd = const <Object?>[],
    this.htmlAttributes = const <String, String?>{},
    this.bodyAttributes = const <String, String?>{},
    this.body,
  });

  /// The document language. The deepest declaration wins.
  final String? language;

  /// The base URL used to resolve relative document resources.
  final String? baseHref;

  /// The page title. The deepest declaration wins.
  final String? title;

  /// The search-result description. The deepest declaration wins.
  final String? description;

  /// The canonical URL. The deepest declaration wins.
  final String? canonical;

  /// Additional metadata, including Open Graph and robots declarations.
  final List<DocumentMeta> meta;

  /// Additional head links, including alternates and preload hints.
  final List<DocumentLink> links;

  /// JSON-LD values emitted as `application/ld+json` scripts.
  final List<Object?> jsonLd;

  /// Attributes merged onto the root html element.
  final Map<String, String?> htmlAttributes;

  /// Attributes merged onto the body element.
  final Map<String, String?> bodyAttributes;

  /// Semantic content, or null when this route only contributes head data.
  final HtmlNode? body;
}
