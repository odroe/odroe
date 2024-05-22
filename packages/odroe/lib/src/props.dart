import 'element.dart';

Iterable? evalProps;

void defineProps<T>(Iterable<T> props) => evalProps = props;

List<T> props<T>() {
  final element = evalElement;
  if (element?.props != null) {
    return element!.props as List<T>;
  }

  return const [];
}
