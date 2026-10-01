import 'page.dart';

/// An immutable, ordered snapshot of Press content.
final class Press {
  /// Creates a snapshot and validates page identity.
  Press(Iterable<PressPage> pages) {
    final ordered = pages.toList(growable: false)..sort(_comparePages);
    final bySlug = <String, PressPage>{};
    final byLocation = <String, PressPage>{};
    for (final page in ordered) {
      final slug = _slugKey(page.slug).toLowerCase();
      final previousSlug = bySlug[slug];
      if (previousSlug != null) {
        throw ArgumentError(
          'Press pages "${previousSlug.sourcePath}" and '
          '"${page.sourcePath}" use the same slug.',
        );
      }
      final location = page.location.toString().toLowerCase();
      final previousLocation = byLocation[location];
      if (previousLocation != null) {
        throw ArgumentError(
          'Press pages "${previousLocation.sourcePath}" and '
          '"${page.sourcePath}" use the same location.',
        );
      }
      bySlug[slug] = page;
      byLocation[location] = page;
    }
    this.pages = List<PressPage>.unmodifiable(ordered);
    _bySlug = Map<String, PressPage>.unmodifiable(bySlug);
  }

  /// Pages sorted by explicit order and then location.
  late final List<PressPage> pages;

  late final Map<String, PressPage> _bySlug;

  /// Static locations represented by this snapshot.
  List<Uri> get locations =>
      List<Uri>.unmodifiable(pages.map((page) => page.location));

  /// Finds a page by path segments relative to the collection mount.
  PressPage? page(Iterable<String> slug) =>
      _bySlug[_slugKey(slug).toLowerCase()];
}

int _comparePages(PressPage left, PressPage right) {
  final order = left.order.compareTo(right.order);
  if (order != 0) return order;
  return left.location.toString().compareTo(right.location.toString());
}

String _slugKey(Iterable<String> slug) => slug.join('\u0000');
