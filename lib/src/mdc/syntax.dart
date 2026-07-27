import 'package:markdown/markdown.dart' as markdown;

import 'ast.dart';
import 'block_syntax.dart';
import 'inline_syntax.dart';
import 'markdown.dart';

final _safeGitHubMarkdown = markdown.ExtensionSet(
  markdown.ExtensionSet.gitHubFlavored.blockSyntaxes,
  <markdown.InlineSyntax>[
    for (final syntax in markdown.ExtensionSet.gitHubFlavored.inlineSyntaxes)
      if (syntax is! markdown.InlineHtmlSyntax) syntax,
  ],
);

/// Parses an MDC body after frontmatter has been removed.
///
/// Applications should use [MdcParser.parse].
List<MdcNode> parseMdcBody(String source) {
  final document = markdown.Document(
    blockSyntaxes: const <markdown.BlockSyntax>[MdcBlockSyntax()],
    inlineSyntaxes: createMdcInlineSyntaxes(),
    extensionSet: _safeGitHubMarkdown,
    encodeHtml: false,
  );
  return convertMarkdownNodes(document.parse(source));
}
