final class Dep<T> {
  Dep._(this.uid, this.value);

  T value;
  Dep? prev;
  Dep? next;
  final int uid;
}

int _uid = 0;
Dep? _evalDep;

Dep<T> createDep<T>(T value) {
  final prev = _evalDep;
  final dep = Dep._(_uid++, value);

  prev?.next = dep;
  dep.prev = prev;

  return dep;
}

void cleanupDep<T>(Dep<T> dep) {
  dep.prev = dep.next;
}

int _depth = -1;

Dep? get _rootDep {
  if (_evalDep == null) return null;

  Dep dep = _evalDep!;
  while (true) {
    if (dep.prev == null) break;
    dep = dep.prev!;
  }

  return dep;
}

Dep? getDepthDep() {
  _depth++;

  Dep? dep = _rootDep;
  for (int depth = 0; depth < _depth; depth++) {
    if (dep == null) break;
    dep = dep.next;
  }

  _depth--;

  return dep;
}

void Function() depth<T>() {
  _depth++;
  return () => _depth--;
}
