import 'element.dart';

Iterable? evalProps;

/// Define a [props] iterable in current sswetup-widget.
void defineProps<T>(Iterable<T> props) => evalProps = props;

/// Returns current setup-widget defined props list.
List<T> props<T>() {
  final element = evalElement;
  if (element?.props != null) {
    return element!.props as List<T>;
  }

  return const [];
}
