import 'element.dart';
import 'reactivity/signals.dart';

Iterable? evalProps;

/// Define a [props] iterable in current sswetup-widget.
void defineProps<T>(Iterable<T> props) => evalProps = props;

/// Returns current setup-widget defined props list.
List<Signal> props() {
  final element = evalElement;
  if (element?.props != null) {
    return element!.props;
  }

  return const [];
}
