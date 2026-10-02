import 'dart:io';

import 'package:path/path.dart' as p;

import '../mdc/ast.dart';
import '../mdc/parser.dart';
import '../press/page.dart';
import '../press/press.dart';

/// Discovers and caches an MDC content directory.
final class PressDirectory {
  /// Creates a file-system content collection.
  PressDirectory(
    String path, {
    String mount = '/',
    this.parser = const MdcParser(),
    this.includeDrafts = false,
  }) : root = Directory(path).absolute,
       mount = _mount(mount);

  /// Absolute content root.
  final Directory root;

  /// Public mount location.
  final Uri mount;

  /// Parser configuration shared by discovered pages.
  final MdcParser parser;

  /// Whether draft pages appear in snapshots and locations.
  final bool includeDrafts;

  final Map<String, _CachedPage> _cache = <String, _CachedPage>{};
  Future<Press>? _loading;
  Press? _snapshot;

  /// Reads a complete immutable snapshot.
  Future<Press> snapshot() {
    final loading = _loading;
    if (loading != null) return loading;
    late final Future<Press> current;
    current = _readSnapshot().whenComplete(() {
      if (identical(_loading, current)) _loading = null;
    });
    _loading = current;
    return current;
  }

  /// Finds one page by path segments relative to [mount].
  Future<PressPage?> page(Iterable<String> slug) async =>
      (await snapshot()).page(slug);

  /// Returns every static page location.
  Future<List<Uri>> locations() async => (await snapshot()).locations;

  Future<Press> _readSnapshot() async {
    if (!root.existsSync()) {
      throw FileSystemException(
        'Press content directory does not exist.',
        root.path,
      );
    }
    final sources = <({File file, String relative})>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.mdc') continue;
      final relative = p.relative(entity.path, from: root.path);
      if (p.split(relative).any((segment) => segment.startsWith('.'))) {
        continue;
      }
      sources.add((file: entity, relative: relative));
    }
    sources.sort((left, right) => left.relative.compareTo(right.relative));

    final pages = <PressPage>[];
    final nextCache = <String, _CachedPage>{};
    for (final source in sources) {
      final page = await _readPage(source.file, source.relative, nextCache);
      if (includeDrafts || !page.draft) pages.add(page);
    }
    try {
      final candidate = Press(pages);
      final previous = _snapshot;
      final press =
          previous != null && _samePages(previous.pages, candidate.pages)
          ? previous
          : candidate;
      _cache
        ..clear()
        ..addAll(nextCache);
      _snapshot = press;
      return press;
    } on ArgumentError catch (error) {
      throw FormatException('${error.message}');
    }
  }

  Future<PressPage> _readPage(
    File file,
    String relative,
    Map<String, _CachedPage> nextCache,
  ) async {
    var stat = await file.stat();
    final cached = _cache[file.path];
    if (cached != null && cached.matches(stat)) {
      nextCache[file.path] = cached;
      return cached.page;
    }

    String? source;
    FileStat? stableStat;
    for (var attempt = 0; attempt < 2; attempt++) {
      source = await file.readAsString();
      final after = await file.stat();
      if (_sameFile(stat, after)) {
        stableStat = after;
        break;
      }
      stat = after;
    }
    if (stableStat == null || source == null) {
      throw FileSystemException(
        'Press content changed while it was being read.',
        relative,
      );
    }

    late final MdcDocument document;
    try {
      document = parser.parse(source);
    } on FormatException catch (error) {
      throw FormatException('${error.message} in $relative');
    }
    final frontmatter = document.frontmatter;
    final title = _requiredString(frontmatter, 'title', relative);
    final description = _optionalString(frontmatter, 'description', relative);
    final order = _optionalInt(frontmatter, 'order', relative) ?? 0;
    final draft = _optionalBool(frontmatter, 'draft', relative) ?? false;
    final language = _optionalString(frontmatter, 'language', relative);
    final slug = _slug(relative);
    final page = PressPage(
      slug: slug,
      location: _location(mount, slug),
      title: title,
      description: description,
      order: order,
      draft: draft,
      language: language,
      content: document,
      sourcePath: p.posix.joinAll(p.split(relative)),
    );
    nextCache[file.path] = _CachedPage(stableStat, page);
    return page;
  }
}

final class _CachedPage {
  _CachedPage(FileStat stat, this.page)
    : size = stat.size,
      modified = stat.modified,
      changed = stat.changed;

  final int size;
  final DateTime modified;
  final DateTime changed;
  final PressPage page;

  bool matches(FileStat stat) =>
      size == stat.size && modified == stat.modified && changed == stat.changed;
}

Uri _mount(String value) {
  for (final segment in value.split('/')) {
    final decoded = Uri.decodeComponent(segment);
    if (decoded == '.' || decoded == '..') {
      throw ArgumentError.value(
        value,
        'mount',
        'Must not contain dot segments.',
      );
    }
  }
  final mount = Uri.parse(value);
  if (!mount.hasAbsolutePath ||
      mount.hasScheme ||
      mount.hasAuthority ||
      mount.hasQuery ||
      mount.hasFragment) {
    throw ArgumentError.value(
      value,
      'mount',
      'Must be an absolute local path without query or fragment.',
    );
  }
  if (mount.pathSegments.any((segment) => segment.isEmpty)) {
    return Uri(
      path: mount.path == '/' ? '/' : mount.path.replaceAll(RegExp(r'/+$'), ''),
    );
  }
  return mount;
}

List<String> _slug(String relative) {
  final parts = p.split(p.withoutExtension(relative));
  if (parts.isNotEmpty && parts.last == 'index') parts.removeLast();
  return List<String>.unmodifiable(parts);
}

Uri _location(Uri mount, List<String> slug) {
  final segments = <String>[
    ...mount.pathSegments.where((segment) => segment.isNotEmpty),
    ...slug,
  ];
  return segments.isEmpty
      ? Uri(path: '/')
      : Uri(pathSegments: <String>['', ...segments]);
}

bool _sameFile(FileStat left, FileStat right) =>
    left.size == right.size &&
    left.modified == right.modified &&
    left.changed == right.changed;

bool _samePages(List<PressPage> left, List<PressPage> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}

String _requiredString(Map<String, Object?> values, String key, String source) {
  final value = _optionalString(values, key, source);
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Press frontmatter "$key" is required in $source.');
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> values,
  String key,
  String source,
) {
  final value = values[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      'Press frontmatter "$key" must be a string in $source.',
    );
  }
  return value;
}

int? _optionalInt(Map<String, Object?> values, String key, String source) {
  final value = values[key];
  if (value == null) return null;
  if (value is! int) {
    throw FormatException(
      'Press frontmatter "$key" must be an integer in $source.',
    );
  }
  return value;
}

bool? _optionalBool(Map<String, Object?> values, String key, String source) {
  final value = values[key];
  if (value == null) return null;
  if (value is! bool) {
    throw FormatException(
      'Press frontmatter "$key" must be a boolean in $source.',
    );
  }
  return value;
}
