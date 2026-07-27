import 'package:flutter/material.dart';

import '../app_flutter/app.dart';
import '../mdc/ast.dart';
import '../mdc/uri.dart';
import 'component.dart';
import 'renderer.dart';
import 'style.dart';

/// Renders an MDC document as a non-scrolling Flutter widget tree.
final class MdcView extends StatelessWidget {
  /// Creates an embedded MDC document view.
  const MdcView({
    required this.document,
    this.renderer,
    this.components = const <MdcWidgetComponent>[],
    this.style = const MdcStyle(),
    this.uriPolicy = const MdcUriPolicy(),
    this.onLink,
    this.imageBuilder,
    this.selectable = true,
    super.key,
  });

  /// The already parsed document.
  final MdcDocument document;

  /// An optional reusable renderer.
  ///
  /// When present, [components], [style], [onLink], and [imageBuilder] are
  /// ignored.
  final MdcWidgetRenderer? renderer;

  /// Components local to this view.
  ///
  /// They override components with the same name contributed by [MdcModule].
  final List<MdcWidgetComponent> components;

  /// Visual overrides used when [renderer] is absent.
  final MdcStyle style;

  /// URI policy used when [renderer] is absent.
  final MdcUriPolicy uriPolicy;

  /// Link handler used when [renderer] is absent.
  final MdcLinkHandler? onLink;

  /// Image builder used when [renderer] is absent.
  final MdcImageBuilder? imageBuilder;

  /// Whether rendered text participates in Flutter selection.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveRenderer(
      context,
      renderer: renderer,
      components: components,
      style: style,
      uriPolicy: uriPolicy,
      onLink: onLink,
      imageBuilder: imageBuilder,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: resolved.style.blockSpacing,
      children: resolved.buildBlocks(context, document),
    );
    return selectable ? SelectionArea(child: content) : content;
  }
}

/// Lazily renders an MDC document as a scrolling list.
final class MdcListView extends StatelessWidget {
  /// Creates a lazy scrolling MDC document view.
  const MdcListView({
    required this.document,
    this.renderer,
    this.components = const <MdcWidgetComponent>[],
    this.style = const MdcStyle(),
    this.uriPolicy = const MdcUriPolicy(),
    this.onLink,
    this.imageBuilder,
    this.selectable = true,
    this.padding,
    this.controller,
    this.physics,
    this.primary,
    super.key,
  });

  /// The already parsed document.
  final MdcDocument document;

  /// An optional reusable renderer.
  final MdcWidgetRenderer? renderer;

  /// Components local to this view.
  final List<MdcWidgetComponent> components;

  /// Visual overrides used when [renderer] is absent.
  final MdcStyle style;

  /// URI policy used when [renderer] is absent.
  final MdcUriPolicy uriPolicy;

  /// Link handler used when [renderer] is absent.
  final MdcLinkHandler? onLink;

  /// Image builder used when [renderer] is absent.
  final MdcImageBuilder? imageBuilder;

  /// Whether rendered text participates in Flutter selection.
  final bool selectable;

  /// Insets around the document blocks.
  final EdgeInsetsGeometry? padding;

  /// Scroll position controller.
  final ScrollController? controller;

  /// Scroll behavior for the document.
  final ScrollPhysics? physics;

  /// Whether this is the primary scroll view.
  final bool? primary;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveRenderer(
      context,
      renderer: renderer,
      components: components,
      style: style,
      uriPolicy: uriPolicy,
      onLink: onLink,
      imageBuilder: imageBuilder,
    );
    final content = ListView.separated(
      padding: padding,
      controller: controller,
      physics: physics,
      primary: primary,
      itemCount: document.nodes.length,
      separatorBuilder: (_, _) => SizedBox(height: resolved.style.blockSpacing),
      itemBuilder: (context, index) =>
          resolved.buildNode(context, document.nodes[index]),
    );
    return selectable ? SelectionArea(child: content) : content;
  }
}

/// Lazily renders an MDC document inside a [CustomScrollView].
final class MdcSliver extends StatelessWidget {
  /// Creates a lazy MDC sliver.
  const MdcSliver({
    required this.document,
    this.renderer,
    this.components = const <MdcWidgetComponent>[],
    this.style = const MdcStyle(),
    this.uriPolicy = const MdcUriPolicy(),
    this.onLink,
    this.imageBuilder,
    super.key,
  });

  /// The already parsed document.
  final MdcDocument document;

  /// An optional reusable renderer.
  final MdcWidgetRenderer? renderer;

  /// Components local to this sliver.
  final List<MdcWidgetComponent> components;

  /// Visual overrides used when [renderer] is absent.
  final MdcStyle style;

  /// URI policy used when [renderer] is absent.
  final MdcUriPolicy uriPolicy;

  /// Link handler used when [renderer] is absent.
  final MdcLinkHandler? onLink;

  /// Image builder used when [renderer] is absent.
  final MdcImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveRenderer(
      context,
      renderer: renderer,
      components: components,
      style: style,
      uriPolicy: uriPolicy,
      onLink: onLink,
      imageBuilder: imageBuilder,
    );
    return SliverList.separated(
      itemCount: document.nodes.length,
      separatorBuilder: (_, _) => SizedBox(height: resolved.style.blockSpacing),
      itemBuilder: (context, index) =>
          resolved.buildNode(context, document.nodes[index]),
    );
  }
}

MdcWidgetRenderer _resolveRenderer(
  BuildContext context, {
  required MdcWidgetRenderer? renderer,
  required Iterable<MdcWidgetComponent> components,
  required MdcStyle style,
  required MdcUriPolicy uriPolicy,
  required MdcLinkHandler? onLink,
  required MdcImageBuilder? imageBuilder,
}) {
  if (renderer != null) return renderer;
  final app = context.maybeAppContext;
  if (app != null) {
    return MdcWidgetRenderer.fromApp(
      app,
      components: components,
      style: style,
      uriPolicy: uriPolicy,
      onLink: onLink,
      imageBuilder: imageBuilder,
    );
  }
  return MdcWidgetRenderer(
    components: components,
    style: style,
    uriPolicy: uriPolicy,
    onLink: onLink,
    imageBuilder: imageBuilder,
  );
}
