import 'package:flutter/material.dart';

/// Visual overrides used by Flutter MDC renderers.
///
/// Unset values inherit from the nearest Material [Theme].
final class MdcStyle {
  /// Creates a set of optional MDC style overrides.
  const MdcStyle({
    this.text,
    this.heading1,
    this.heading2,
    this.heading3,
    this.heading4,
    this.heading5,
    this.heading6,
    this.link,
    this.inlineCode,
    this.codeBlock,
    this.listMarker,
    this.blockquote,
    this.blockSpacing = 16,
    this.codeBlockPadding = const EdgeInsets.all(16),
    this.blockquotePadding = const EdgeInsetsDirectional.only(start: 16),
    this.tableCellPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    this.codeBlockDecoration,
    this.blockquoteDecoration,
    this.tableBorder,
  });

  /// Body text style.
  final TextStyle? text;

  /// Level-one heading style.
  final TextStyle? heading1;

  /// Level-two heading style.
  final TextStyle? heading2;

  /// Level-three heading style.
  final TextStyle? heading3;

  /// Level-four heading style.
  final TextStyle? heading4;

  /// Level-five heading style.
  final TextStyle? heading5;

  /// Level-six heading style.
  final TextStyle? heading6;

  /// Link text style.
  final TextStyle? link;

  /// Inline code style.
  final TextStyle? inlineCode;

  /// Fenced and indented code-block style.
  final TextStyle? codeBlock;

  /// Ordered and unordered list-marker style.
  final TextStyle? listMarker;

  /// Blockquote text style.
  final TextStyle? blockquote;

  /// Vertical space between top-level blocks.
  final double blockSpacing;

  /// Padding inside a code block.
  final EdgeInsetsGeometry codeBlockPadding;

  /// Padding inside a blockquote.
  final EdgeInsetsGeometry blockquotePadding;

  /// Padding inside a table cell.
  final EdgeInsetsGeometry tableCellPadding;

  /// Decoration around code blocks.
  final BoxDecoration? codeBlockDecoration;

  /// Decoration around blockquotes.
  final BoxDecoration? blockquoteDecoration;

  /// Border used for Markdown tables.
  final TableBorder? tableBorder;
}
