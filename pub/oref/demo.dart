import 'src/core/impls/flags.dart';

main() {
  final flags = Flags.dirty | Flags.notified;
  print(flags & Flags.active);
}
