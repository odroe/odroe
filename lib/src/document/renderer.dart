import 'dart:convert';

import 'document.dart';
import 'node.dart';

/// A fully merged route document ready for HTML rendering.
final class ResolvedDocument {
  const ResolvedDocument._({
    required this.language,
    required this.baseHref,
    required this.title,
    required this.meta,
    required this.links,
    required this.jsonLd,
    required this.htmlAttributes,
    required this.bodyAttributes,
    required this.body,
  });

  /// The resolved document language.
  final String? language;

  /// The resolved base URL.
  final String? baseHref;

  /// The resolved page title.
  final String? title;

  /// Deduplicated metadata in stable document order.
  final List<DocumentMeta> meta;

  /// Deduplicated head links in stable document order.
  final List<DocumentLink> links;

  /// JSON-LD values in route order.
  final List<Object?> jsonLd;

  /// Merged root html attributes.
  final Map<String, String?> htmlAttributes;

  /// Merged body attributes.
  final Map<String, String?> bodyAttributes;

  /// The composed semantic body.
  final HtmlNode? body;
}

/// Merges route-owned document fragments from root to leaf.
ResolvedDocument resolveDocument(Iterable<RouteDocument> documents) {
  String? language;
  String? baseHref;
  String? title;
  final meta = <String, DocumentMeta>{};
  final links = <String, DocumentLink>{};
  final jsonLd = <Object?>[];
  final htmlAttributes = <String, String?>{};
  final bodyAttributes = <String, String?>{};
  HtmlNode? body;

  for (final document in documents) {
    language = document.language ?? language;
    baseHref = document.baseHref ?? baseHref;
    title = document.title ?? title;
    if (document.description case final description?) {
      const key = 'name:description';
      meta[key] = DocumentMeta.name('description', description);
    }
    for (final item in document.meta) {
      meta[item.identity] = item;
    }
    if (document.canonical case final canonical?) {
      links['canonical'] = DocumentLink(rel: 'canonical', href: canonical);
    }
    for (final item in document.links) {
      links[item.identity] = item;
    }
    jsonLd.addAll(document.jsonLd);
    htmlAttributes.addAll(document.htmlAttributes);
    bodyAttributes.addAll(document.bodyAttributes);

    final nextBody = document.body;
    if (nextBody == null) continue;
    if (body == null) {
      body = nextBody;
      continue;
    }
    final inserted = _insertOutlet(body, nextBody);
    if (identical(inserted, body)) {
      throw StateError(
        'A parent route document with descendant body content must contain '
        'an HtmlOutlet.',
      );
    }
    body = inserted;
  }

  return ResolvedDocument._(
    language: language,
    baseHref: baseHref,
    title: title,
    meta: List<DocumentMeta>.unmodifiable(meta.values),
    links: List<DocumentLink>.unmodifiable(links.values),
    jsonLd: List<Object?>.unmodifiable(jsonLd),
    htmlAttributes: Map<String, String?>.unmodifiable(htmlAttributes),
    bodyAttributes: Map<String, String?>.unmodifiable(bodyAttributes),
    body: body == null ? null : _removeOutlets(body),
  );
}

/// Renders a resolved document's opening HTML, head, and semantic body.
///
/// The returned source intentionally omits the closing body and html tags so
/// Start can append handoff frames while queries are still resolving.
String renderDocumentStart(ResolvedDocument document, {String? baseHref}) {
  final output = StringBuffer('<!doctype html><html');
  final htmlAttributes = <String, String?>{
    'lang': ?document.language,
    ...document.htmlAttributes,
  };
  _writeAttributes(output, htmlAttributes);
  output.write('><head><meta charset="utf-8">');
  output.write(
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
  );
  final resolvedBaseHref = baseHref ?? document.baseHref;
  if (resolvedBaseHref != null) {
    output.write('<base');
    _writeAttributes(output, <String, String?>{'href': resolvedBaseHref});
    output.write('>');
  }
  if (document.title case final title?) {
    output
      ..write('<title>')
      ..write(_escapeText(title))
      ..write('</title>');
  }
  for (final item in document.meta) {
    output.write('<meta');
    if (item.charset case final charset?) {
      _writeAttributes(output, <String, String?>{'charset': charset});
    } else {
      _writeAttributes(output, <String, String?>{
        item.attribute!: item.key,
        'content': item.content,
      });
    }
    output.write('>');
  }
  for (final item in document.links) {
    output.write('<link');
    _writeAttributes(output, <String, String?>{
      'rel': item.rel,
      'href': item.href,
      'hreflang': ?item.hreflang,
      'media': ?item.media,
      'type': ?item.type,
      'as': ?item.as,
      'crossorigin': ?item.crossorigin,
    });
    output.write('>');
  }
  for (final value in document.jsonLd) {
    final encoded = jsonEncode(value).replaceAllMapped(
      RegExp(r'</script', caseSensitive: false),
      (_) => r'<\/script',
    );
    output
      ..write('<script type="application/ld+json">')
      ..write(encoded)
      ..write('</script>');
  }
  output.write('</head><body');
  _writeAttributes(output, document.bodyAttributes);
  output.write('>');
  if (document.body case final body?) {
    output.write('<div id="__odroe_document__">');
    _writeNode(output, body);
    output.write('</div>');
  }
  return output.toString();
}

HtmlNode _insertOutlet(HtmlNode node, HtmlNode child) {
  if (node is HtmlOutlet) return child;
  if (node is HtmlElement) {
    for (var index = 0; index < node.children.length; index++) {
      final current = node.children[index];
      final inserted = _insertOutlet(current, child);
      if (!identical(current, inserted)) {
        return HtmlElement(
          node.tag,
          attributes: node.attributes,
          children: <HtmlNode>[
            ...node.children.take(index),
            inserted,
            ...node.children.skip(index + 1),
          ],
        );
      }
    }
    return node;
  }
  if (node is HtmlFragment) {
    for (var index = 0; index < node.children.length; index++) {
      final current = node.children[index];
      final inserted = _insertOutlet(current, child);
      if (!identical(current, inserted)) {
        return HtmlFragment(<HtmlNode>[
          ...node.children.take(index),
          inserted,
          ...node.children.skip(index + 1),
        ]);
      }
    }
  }
  return node;
}

HtmlNode _removeOutlets(HtmlNode node) {
  if (node is HtmlOutlet) return const HtmlFragment(<HtmlNode>[]);
  if (node is HtmlElement) {
    return HtmlElement(
      node.tag,
      attributes: node.attributes,
      children: node.children.map(_removeOutlets).toList(growable: false),
    );
  }
  if (node is HtmlFragment) {
    return HtmlFragment(
      node.children.map(_removeOutlets).toList(growable: false),
    );
  }
  return node;
}

void _writeNode(StringBuffer output, HtmlNode node) {
  switch (node) {
    case HtmlText(:final value):
      output.write(_escapeText(value));
    case HtmlFragment(:final children):
      for (final child in children) {
        _writeNode(output, child);
      }
    case HtmlElement(:final tag, :final attributes, :final children):
      if (!_tag.hasMatch(tag)) {
        throw FormatException('Invalid HTML tag: $tag');
      }
      output.write('<$tag');
      _writeAttributes(output, attributes);
      output.write('>');
      final voidElement = _voidElements.contains(tag.toLowerCase());
      if (voidElement && children.isNotEmpty) {
        throw StateError('Void HTML element <$tag> cannot have children.');
      }
      if (!voidElement) {
        for (final child in children) {
          _writeNode(output, child);
        }
        output.write('</$tag>');
      }
    case HtmlOutlet():
      throw StateError('Unresolved HtmlOutlet.');
  }
}

void _writeAttributes(StringBuffer output, Map<String, String?> attributes) {
  for (final entry in attributes.entries) {
    if (!_attribute.hasMatch(entry.key)) {
      throw FormatException('Invalid HTML attribute: ${entry.key}');
    }
    output
      ..write(' ')
      ..write(entry.key);
    if (entry.value case final value?) {
      output
        ..write('="')
        ..write(_escapeAttribute(value))
        ..write('"');
    }
  }
}

String _escapeText(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);

String _escapeAttribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

final RegExp _tag = RegExp(r'^[A-Za-z][A-Za-z0-9-]*$');
final RegExp _attribute = RegExp(r'^[A-Za-z_:][A-Za-z0-9_:.-]*$');
const Set<String> _voidElements = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};
