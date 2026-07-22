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
    final nodes = parseMdcBody(body);
    late MdcDocument document;
    try {
      document = MdcDocument(nodes: nodes, frontmatter: frontmatter);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid MDC frontmatter: ${error.message}');
    } on TypeError {
      throw const FormatException('MDC frontmatter keys must be strings.');
    }
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
        : (parsed as Map<Object?, Object?>).cast<String, Object?>(),
  );
}
