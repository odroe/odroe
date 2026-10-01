import 'package:odroe/document.dart';

HtmlElement element(
  String tag, {
  Map<String, String?> attributes = const <String, String?>{},
  List<HtmlNode> children = const <HtmlNode>[],
}) => HtmlElement(tag, attributes: attributes, children: children);

HtmlText text(String value) => HtmlText(value);
