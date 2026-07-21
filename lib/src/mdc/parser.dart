import 'package:yaml/yaml.dart';

import 'ast.dart';
import 'outline.dart';
import 'syntax.dart';

/// Transforms one parsed immutable MDC document.
typedef MdcTransform = MdcDocument Function(MdcDocument document);

/// Parses Markdown Components source into an immutable, renderer-neutral AST.
///
/// A parser is reusable but deliberately holds no source cache. The content
/// owner can cache completed [MdcDocument] values using its own lifecycle and
/// invalidation rules.
final class MdcParser {
  /// Creates a reusable parser configuration.
  const MdcParser({
    this.transforms = const <MdcTransform>[],
    this.headingIds = true,
  });

  /// Ordered transforms applied after syntax parsing.
  final List<MdcTransform> transforms;

  /// Whether headings without explicit IDs receive stable generated IDs.
  final bool headingIds;

  /// Parses [source].
  ///
  /// A YAML mapping fenced by `---` at the beginning of the source becomes
  /// [MdcDocument.frontmatter]. Raw HTML remains text and is never interpreted
  /// by the parser.
  MdcDocument parse(String source) {
    final (:body, :frontmatter) = _readFrontmatter(source);
    var document = MdcDocument(
      nodes: parseMdcBody(body),
      frontmatter: frontmatter,
    );
    for (final transform in transforms) {
      document = transform(document);
    }
    return headingIds ? document.withHeadingIds() : document;
  }
}

({String body, Map<String, Object?> frontmatter}) _readFrontmatter(
  String source,
) {
  final normalized = source.startsWith('\u{feff}')
      ? source.substring(1)
      : source;
  final lines = normalized.split('\n');
  if (lines.isEmpty || lines.first.trimRight() != '---') {
    return (body: normalized, frontmatter: const <String, Object?>{});
  }

  var end = 1;
  while (end < lines.length && lines[end].trimRight() != '---') {
    end++;
  }
  if (end == lines.length) {
    throw const FormatException('Unclosed MDC frontmatter.');
  }

  final yamlSource = lines.sublist(1, end).join('\n');
  final Object? parsed;
  try {
    parsed = loadYaml(yamlSource);
  } on YamlException catch (error) {
    throw FormatException('Invalid MDC frontmatter: ${error.message}');
  }
  if (parsed != null && parsed is! Map<Object?, Object?>) {
    throw const FormatException('MDC frontmatter must be a YAML mapping.');
  }

  return (
    body: lines.skip(end + 1).join('\n'),
    frontmatter: parsed == null
        ? const <String, Object?>{}
        : _normalizeMap(parsed as Map<Object?, Object?>, 'frontmatter'),
  );
}

Map<String, Object?> _normalizeMap(
  Map<Object?, Object?> source,
  String location,
) {
  final result = <String, Object?>{};
  for (final MapEntry(:key, :value) in source.entries) {
    if (key is! String) {
      throw FormatException('MDC $location keys must be strings.');
    }
    result[key] = _normalizeValue(value, '$location.$key');
  }
  return result;
}

Object? _normalizeValue(Object? value, String location) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw FormatException('MDC $location must be finite.');
    }
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return _normalizeMap(value, location);
  }
  if (value is Iterable<Object?>) {
    var index = 0;
    return <Object?>[
      for (final item in value) _normalizeValue(item, '$location[${index++}]'),
    ];
  }
  throw FormatException(
    'MDC $location contains unsupported ${value.runtimeType}.',
  );
}
