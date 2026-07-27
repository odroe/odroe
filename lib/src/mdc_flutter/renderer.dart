import 'package:flutter/material.dart';

import '../app/context.dart';
import '../mdc/ast.dart';
import '../mdc/component.dart';
import '../mdc/uri.dart';
import 'component.dart';
import 'style.dart';

/// Handles a link activated by rendered MDC content.
typedef MdcLinkHandler = void Function(BuildContext context, Uri location);

/// Builds an image found in rendered MDC content.
typedef MdcImageBuilder =
    Widget Function(BuildContext context, Uri source, String? description);

/// Converts an immutable [MdcDocument] into Flutter widgets.
final class MdcWidgetRenderer {
  /// Creates a Flutter renderer with explicit [components].
  MdcWidgetRenderer({
    Iterable<MdcWidgetComponent> components = const <MdcWidgetComponent>[],
    this.style = const MdcStyle(),
    this.uriPolicy = const MdcUriPolicy(),
    this.onLink,
    this.imageBuilder,
  }) : _components = _componentMap(components);

  MdcWidgetRenderer._({
    required Map<String, MdcWidgetComponent> components,
    required this.style,
    required this.uriPolicy,
    required this.onLink,
    required this.imageBuilder,
  }) : _components = components;

  /// Creates a renderer from module components and optional local overrides.
  factory MdcWidgetRenderer.fromApp(
    AppContext app, {
    Iterable<MdcWidgetComponent> components = const <MdcWidgetComponent>[],
    MdcStyle style = const MdcStyle(),
    MdcUriPolicy uriPolicy = const MdcUriPolicy(),
    MdcLinkHandler? onLink,
    MdcImageBuilder? imageBuilder,
  }) {
    final resolved = _componentMap(
      app.bindings<MdcComponentBinding>().whereType<MdcWidgetComponent>(),
    );
    for (final component in components) {
      _validateComponent(component);
      resolved[component.name] = component;
    }
    return MdcWidgetRenderer._(
      components: resolved,
      style: style,
      uriPolicy: uriPolicy,
      onLink: onLink,
      imageBuilder: imageBuilder,
    );
  }

  final Map<String, MdcWidgetComponent> _components;

  /// Visual overrides for standard Markdown elements.
  final MdcStyle style;

  /// URI policy shared with semantic HTML rendering.
  final MdcUriPolicy uriPolicy;

  /// Optional link activation handler.
  final MdcLinkHandler? onLink;

  /// Optional image builder.
  final MdcImageBuilder? imageBuilder;

  /// Builds all top-level blocks without adding a scrolling container.
  List<Widget> buildBlocks(BuildContext context, MdcDocument document) =>
      <Widget>[for (final node in document.nodes) buildNode(context, node)];

  /// Builds one document node for custom layouts and lazy lists.
  Widget buildNode(BuildContext context, MdcNode node) =>
      _buildBlock(context, node);

  Widget _buildBlock(BuildContext context, MdcNode node) => switch (node) {
    MdcText(:final value) => Text(value, style: _bodyStyle(context)),
    MdcComponent() => _buildComponent(context, node),
    MdcElement(:final tag) => switch (tag) {
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' => _buildHeading(context, node, int.parse(tag.substring(1))),
      'p' => _richText(context, node.children),
      'blockquote' => _buildBlockquote(context, node),
      'pre' => _buildCodeBlock(context, node),
      'ul' => _buildList(context, node, ordered: false),
      'ol' => _buildList(context, node, ordered: true),
      'table' => _buildTable(context, node),
      'hr' => const Divider(),
      'img' => _buildImage(context, node),
      'li' => _buildChildren(context, node.children),
      _ => _buildChildren(context, node.children),
    },
  };

  Widget _buildHeading(BuildContext context, MdcElement element, int level) =>
      Semantics(
        header: true,
        headingLevel: level,
        child: _richText(
          context,
          element.children,
          style: _headingStyle(context, level),
        ),
      );

  Widget _buildChildren(BuildContext context, Iterable<MdcNode> nodes) {
    final children = <Widget>[
      for (final node in nodes) _buildBlock(context, node),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: style.blockSpacing,
      children: children,
    );
  }

  Widget _richText(
    BuildContext context,
    Iterable<MdcNode> nodes, {
    TextStyle? style,
  }) => Text.rich(
    TextSpan(
      style: style ?? _bodyStyle(context),
      children: <InlineSpan>[
        for (final node in nodes) _buildInline(context, node),
      ],
    ),
  );

  InlineSpan _buildInline(BuildContext context, MdcNode node) => switch (node) {
    MdcText(:final value) => TextSpan(text: value),
    MdcComponent() => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _buildComponent(context, node),
    ),
    MdcElement(:final tag) => switch (tag) {
      'strong' => _inlineChildren(
        context,
        node.children,
        const TextStyle(fontWeight: FontWeight.bold),
      ),
      'em' => _inlineChildren(
        context,
        node.children,
        const TextStyle(fontStyle: FontStyle.italic),
      ),
      'del' => _inlineChildren(
        context,
        node.children,
        const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      'code' => _inlineChildren(
        context,
        node.children,
        _inlineCodeStyle(context),
      ),
      'a' => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _buildLink(context, node),
      ),
      'img' => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _buildImage(context, node),
      ),
      'input' => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(
          node.attributes.containsKey('checked')
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          size: _bodyStyle(context).fontSize,
        ),
      ),
      'br' => const TextSpan(text: '\n'),
      'sup' => _inlineChildren(
        context,
        node.children,
        const TextStyle(
          fontFeatures: <FontFeature>[FontFeature.superscripts()],
        ),
      ),
      'sub' => _inlineChildren(
        context,
        node.children,
        const TextStyle(fontFeatures: <FontFeature>[FontFeature.subscripts()]),
      ),
      _ => _inlineChildren(context, node.children, null),
    },
  };

  TextSpan _inlineChildren(
    BuildContext context,
    Iterable<MdcNode> nodes,
    TextStyle? textStyle,
  ) => TextSpan(
    style: textStyle,
    children: <InlineSpan>[
      for (final child in nodes) _buildInline(context, child),
    ],
  );

  Widget _buildLink(BuildContext context, MdcElement element) {
    final href = element.attributes['href'];
    final safe = href == null ? null : uriPolicy.link(href);
    final location = safe == null ? null : Uri.tryParse(safe);
    final text = _richText(
      context,
      element.children,
      style: _linkStyle(context),
    );
    final handler = onLink;
    if (location == null || handler == null) return text;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => handler(context, location),
        child: text,
      ),
    );
  }

  Widget _buildImage(BuildContext context, MdcElement element) {
    final safe = uriPolicy.image(element.attributes['src'] ?? '');
    final source = safe == null ? null : Uri.tryParse(safe);
    if (source == null) return const SizedBox.shrink();
    final description = element.attributes['alt'];
    final builder = imageBuilder;
    if (builder != null) return builder(context, source, description);
    if (source.hasScheme) {
      return Image.network(source.toString(), semanticLabel: description);
    }
    return Image.asset(source.toString(), semanticLabel: description);
  }

  Widget _buildBlockquote(BuildContext context, MdcElement element) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration:
          style.blockquoteDecoration ??
          BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 4,
              ),
            ),
          ),
      child: Padding(
        padding: style.blockquotePadding,
        child: DefaultTextStyle.merge(
          style:
              style.blockquote ??
              _bodyStyle(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          child: _buildChildren(context, element.children),
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, MdcElement element) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration:
          style.codeBlockDecoration ??
          BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: style.codeBlockPadding,
        child: Text(
          _textContent(element),
          style:
              style.codeBlock ??
              theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    MdcElement element, {
    required bool ordered,
  }) {
    final items = element.children
        .whereType<MdcElement>()
        .where((element) => element.tag == 'li')
        .toList(growable: false);
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: style.blockSpacing / 2,
      children: <Widget>[
        for (var index = 0; index < items.length; index++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 32,
                child: Text(
                  ordered ? '${start + index}.' : '\u2022',
                  textAlign: TextAlign.end,
                  style: style.listMarker ?? _bodyStyle(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildChildren(context, items[index].children)),
            ],
          ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, MdcElement table) {
    final rows = <MdcElement>[];
    void collect(MdcNode node) {
      if (node case MdcElement(tag: 'tr')) {
        rows.add(node);
        return;
      }
      if (node case MdcElement(:final children)) {
        children.forEach(collect);
      }
    }

    table.children.forEach(collect);
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border:
            style.tableBorder ??
            TableBorder.all(color: theme.colorScheme.outlineVariant),
        children: <TableRow>[
          for (final row in rows)
            TableRow(
              children: <Widget>[
                for (final cell in row.children.whereType<MdcElement>())
                  Padding(
                    padding: style.tableCellPadding,
                    child: _richText(
                      context,
                      cell.children,
                      style: cell.tag == 'th'
                          ? _bodyStyle(
                              context,
                            ).copyWith(fontWeight: FontWeight.bold)
                          : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildComponent(BuildContext context, MdcComponent node) {
    final component = _components[node.name];
    if (component == null) {
      throw MdcUnknownComponentException(node.name);
    }
    return component.builder(
      MdcWidgetComponentContext(
        context: context,
        name: node.name,
        properties: node.properties,
        children: _buildChildren(context, node.children),
        slots: Map<String, MdcWidgetSlot>.unmodifiable(<String, MdcWidgetSlot>{
          for (final MapEntry(:key, :value) in node.slots.entries)
            key: MdcWidgetSlot(
              properties: value.properties,
              children: _buildChildren(context, value.children),
            ),
        }),
      ),
    );
  }

  TextStyle _bodyStyle(BuildContext context) =>
      style.text ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

  TextStyle _headingStyle(BuildContext context, int level) {
    final theme = Theme.of(context).textTheme;
    return switch (level) {
          1 => style.heading1 ?? theme.headlineLarge,
          2 => style.heading2 ?? theme.headlineMedium,
          3 => style.heading3 ?? theme.headlineSmall,
          4 => style.heading4 ?? theme.titleLarge,
          5 => style.heading5 ?? theme.titleMedium,
          _ => style.heading6 ?? theme.titleSmall,
        } ??
        _bodyStyle(context);
  }

  TextStyle _linkStyle(BuildContext context) =>
      style.link ??
      _bodyStyle(context).copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );

  TextStyle _inlineCodeStyle(BuildContext context) =>
      style.inlineCode ??
      _bodyStyle(context).copyWith(
        fontFamily: 'monospace',
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
}

Map<String, MdcWidgetComponent> _componentMap(
  Iterable<MdcWidgetComponent> components,
) {
  final result = <String, MdcWidgetComponent>{};
  for (final component in components) {
    _validateComponent(component);
    if (result.containsKey(component.name)) {
      throw StateError(
        'Flutter MDC component "${component.name}" is registered twice.',
      );
    }
    result[component.name] = component;
  }
  return result;
}

void _validateComponent(MdcWidgetComponent component) {
  if (component.name.isEmpty) {
    throw ArgumentError.value(
      component.name,
      'components',
      'An MDC component name cannot be empty.',
    );
  }
}

String _textContent(MdcNode node) => switch (node) {
  MdcText(:final value) => value,
  MdcElement(:final children) => children.map(_textContent).join(),
  MdcComponent(:final children) => children.map(_textContent).join(),
};
