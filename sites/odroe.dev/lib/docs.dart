import 'package:odroe/press.dart';

/// One documentation request with an immutable navigation snapshot.
final class DocsData {
  DocsData({required this.page, required Iterable<PressPage> navigation})
    : navigation = List<PressPage>.unmodifiable(navigation);

  final PressPage page;
  final List<PressPage> navigation;
}
