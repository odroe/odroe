import '../app/context.dart';
import '../document/node.dart';
import 'ast.dart';
import 'component.dart';
import 'uri.dart';

/// Converts an immutable MDC document into semantic [HtmlNode] values.
final class MdcHtmlRenderer {
  /// Creates a standalone renderer with explicit [components].
  factory MdcHtmlRenderer({
    Iterable<MdcHtmlComponent> components = const <MdcHtmlComponent>[],
    MdcUriPolicy uriPolicy = const MdcUriPolicy(),
    MdcHtmlComponentBuilder? unknownComponent,
  }) => MdcHtmlRenderer._(
    _indexComponents(components),
    uriPolicy,
    unknownComponent,
  );

  /// Creates a renderer from components installed in [app].
  factory MdcHtmlRenderer.fromApp(
    AppContext app, {
    MdcUriPolicy uriPolicy = const MdcUriPolicy(),
    MdcHtmlComponentBuilder? unknownComponent,
  }) => MdcHtmlRenderer(
    components: app.bindings<MdcHtmlComponent>(),
    uriPolicy: uriPolicy,
    unknownComponent: unknownComponent,
  );

  const MdcHtmlRenderer._(
    this._components,
    this.uriPolicy,
    this.unknownComponent,
  );

  final Map<String, MdcHtmlComponent> _components;

  /// The URI policy applied to links and images.
  final MdcUriPolicy uriPolicy;

  /// Optional renderer for component names absent from [components].
  ///
  /// When omitted, an unresolved component throws an
  /// [MdcUnknownComponentException].
  final MdcHtmlComponentBuilder? unknownComponent;

  /// Renders [document] as a transparent HTML fragment.
  HtmlFragment render(MdcDocument document) => _renderNodes(document.nodes);

  HtmlFragment _renderNodes(Iterable<MdcNode> nodes) =>
      HtmlFragment(List<HtmlNode>.unmodifiable(nodes.map(_renderNode)));

  HtmlNode _renderNode(MdcNode node) {
    return switch (node) {
      MdcText(:final value) => HtmlText(value),
      MdcElement(:final tag, :final attributes, :final children) =>
        _renderElement(tag, attributes, children),
      MdcComponent(
        :final name,
        :final properties,
        :final children,
        :final slots,
      ) =>
        _renderComponent(name, properties, children, slots),
    };
  }

  HtmlNode _renderElement(
    String sourceTag,
    Map<String, String?> sourceAttributes,
    List<MdcNode> children,
  ) {
    final tag = sourceTag.toLowerCase();
    if (!_htmlTags.contains(tag)) {
      throw MdcHtmlRenderException(
        'Unsupported Markdown HTML tag "$sourceTag".',
      );
    }
    final attributes = _renderAttributes(tag, sourceAttributes);
    return HtmlElement(
      tag,
      attributes: attributes,
      children: List<HtmlNode>.unmodifiable(children.map(_renderNode)),
    );
  }

  HtmlNode _renderComponent(
    String name,
    Map<String, Object?> properties,
    List<MdcNode> children,
    Map<String, MdcSlot> slots,
  ) {
    final component = _components[name];
    final builder = component?.builder ?? unknownComponent;
    if (builder == null) throw MdcUnknownComponentException(name);
    final context = MdcHtmlComponentContext(
      name: name,
      properties: properties,
      children: _renderNodes(children),
      slots: Map<String, MdcHtmlSlot>.unmodifiable(<String, MdcHtmlSlot>{
        for (final entry in slots.entries)
          entry.key: MdcHtmlSlot(
            properties: entry.value.properties,
            children: _renderNodes(entry.value.children),
          ),
      }),
    );
    return builder(context);
  }

  Map<String, String?> _renderAttributes(
    String tag,
    Map<String, String?> source,
  ) {
    if (source.isEmpty) return const <String, String?>{};
    final output = <String, String?>{};
    for (final entry in source.entries) {
      final name = entry.key.toLowerCase();
      final value = entry.value;
      if (!_allowsAttribute(tag, name)) continue;
      if (name == 'href') {
        if (value case final value?) {
          if (uriPolicy.link(value) case final safe?) output[name] = safe;
        }
        continue;
      }
      if (name == 'src') {
        if (value case final value?) {
          if (uriPolicy.image(value) case final safe?) output[name] = safe;
        }
        continue;
      }
      if (name == 'target' && !_linkTargets.contains(value)) continue;
      if (_integerAttributes.contains(name) && !_isPositiveInteger(value)) {
        continue;
      }
      output[name] = value;
    }

    if (tag == 'a' && output['target'] == '_blank') {
      final rel = (output['rel'] ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty);
      output['rel'] = <String>{...rel, 'noopener', 'noreferrer'}.join(' ');
    }
    if (tag == 'input') {
      if (output['type']?.toLowerCase() != 'checkbox') {
        throw const MdcHtmlRenderException(
          'Only task-list checkbox inputs are supported.',
        );
      }
      output['type'] = 'checkbox';
      output['disabled'] = null;
      if (output['checked'] case final checked?) {
        if (checked.isEmpty ||
            checked == 'checked' ||
            checked.toLowerCase() == 'true') {
          output['checked'] = null;
        } else {
          output.remove('checked');
        }
      } else if (output.containsKey('checked')) {
        output['checked'] = null;
      }
    }
    return Map<String, String?>.unmodifiable(output);
  }
}

/// A failure to convert an MDC node into safe semantic HTML.
final class MdcHtmlRenderException implements Exception {
  /// Creates an HTML rendering exception.
  const MdcHtmlRenderException(this.message);

  /// The reason rendering stopped.
  final String message;

  @override
  String toString() => 'MDC HTML render failed: $message';
}

Map<String, MdcHtmlComponent> _indexComponents(
  Iterable<MdcHtmlComponent> components,
) {
  final result = <String, MdcHtmlComponent>{};
  for (final component in components) {
    if (component.name.isEmpty) {
      throw ArgumentError.value(
        component.name,
        'components',
        'An MDC component name cannot be empty.',
      );
    }
    if (result.containsKey(component.name)) {
      throw ArgumentError.value(
        component.name,
        'components',
        'HTML component names must be unique.',
      );
    }
    result[component.name] = component;
  }
  return Map<String, MdcHtmlComponent>.unmodifiable(result);
}

bool _allowsAttribute(String tag, String name) {
  if (_globalAttributes.contains(name) ||
      name.startsWith('aria-') ||
      name.startsWith('data-')) {
    return _attributeName.hasMatch(name);
  }
  return _tagAttributes[tag]?.contains(name) ?? false;
}

bool _isPositiveInteger(String? value) {
  if (value == null) return false;
  final parsed = int.tryParse(value);
  return parsed != null && parsed > 0;
}

final RegExp _attributeName = RegExp(r'^[a-z][a-z0-9_.:-]*$');

const Set<String> _htmlTags = <String>{
  'a',
  'blockquote',
  'br',
  'code',
  'del',
  'em',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'img',
  'input',
  'li',
  'ol',
  'p',
  'pre',
  'section',
  'span',
  'strong',
  'sub',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
};

const Set<String> _globalAttributes = <String>{
  'class',
  'dir',
  'id',
  'lang',
  'role',
  'title',
};

const Map<String, Set<String>> _tagAttributes = <String, Set<String>>{
  'a': <String>{'href', 'rel', 'target'},
  'code': <String>{'class'},
  'img': <String>{'alt', 'decoding', 'height', 'loading', 'src', 'width'},
  'input': <String>{'checked', 'disabled', 'type'},
  'li': <String>{'value'},
  'ol': <String>{'reversed', 'start', 'type'},
  'td': <String>{'align', 'colspan', 'rowspan'},
  'th': <String>{'align', 'colspan', 'rowspan', 'scope'},
};

const Set<String?> _linkTargets = <String?>{
  '_blank',
  '_parent',
  '_self',
  '_top',
};

const Set<String> _integerAttributes = <String>{
  'colspan',
  'height',
  'rowspan',
  'width',
};
