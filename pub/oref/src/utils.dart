import 'developer.dart';

/// Check if two objects are not identical
///
/// Returns `true` if the objects are different, `false` if they are the same
bool hasChanged(Object? a, Object? b) => !identical(a, b);

void warn(String message, [Iterable<Object>? other]) {
  if (!dev) return;
  print('[$brand] \x1B[43mwarning\x1B[0m: $message');
  if (other?.isNotEmpty == true) {
    for (final item in other!) {
      print(item);
    }
  }
}
