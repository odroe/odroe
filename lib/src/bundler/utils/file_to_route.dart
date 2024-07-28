import 'package:path/path.dart' as p;

final _paramRegex = RegExp(r'\[(\w+)\]');
final _catchallRegex = RegExp(r'\[...(\w+)?\]');

String fileToRoute(String root, String path) {
  return p
      .relative(p.dirname(path), from: root)
      .replaceAll('\\', '/')
      .replaceAllMapped(_paramRegex, (m) => ':${m[1]}')
      .replaceAllMapped(
        _catchallRegex,
        (m) => switch (m[1]) {
          String name => '**:$name',
          _ => '**',
        },
      )
      .cleanDot();
}

extension on String {
  String cleanDot() {
    if (startsWith('.')) {
      return substring(1);
    }

    return this;
  }
}
