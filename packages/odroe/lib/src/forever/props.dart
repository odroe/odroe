import 'dep.dart';
import 'next/reactivity/signals.dart';

void defineProps(Iterable props) {
  final dep = getDepthDep();
  if (dep is Dep<List<WriteableSignal>>) {
    for (final (index, prop) in props.indexed) {
      final element = dep.value.elementAtOrNull(index);
      if (element != null) {
        element.value = prop;
        continue;
      }

      dep.value[index] = signal(prop);
    }

    return;
  }

  final cleanup = depth();
  createDep(props.map(signal).toList());
  cleanup();
}

List<Signal> props() {
  final dep = getDepthDep();
  if (dep is Dep<List<WriteableSignal>>) {
    return dep.value;
  }

  throw StateError('[odroe] Please use `defineProps` to define props.');
}

main() {
  defineProps([1, 2]);
}
