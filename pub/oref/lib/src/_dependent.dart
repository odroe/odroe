Effect? _activeEffect;

class Ref<T> {
  Ref(this._value);

  T _value;
  final Set<Effect> _deps = {};

  T get value {
    _track();
    return _value;
  }

  set value(T newValue) {
    if (newValue != _value) {
      _value = newValue;
      _trigger();
    }
  }

  void _track() {
    if (_activeEffect != null) {
      _deps.add(_activeEffect!);
      _activeEffect!.deps.add(this);
    }
  }

  void _trigger() {
    for (final effect in [..._deps]) {
      if (_isBatching) {
        _batchedEffects.add(effect);
      } else {
        effect.run();
      }
    }
  }
}

Ref<T> ref<T>(T value) => Ref<T>(value);

class ComputedRef<T> extends Ref<T> {
  ComputedRef(this._compute) : super(_compute());

  final T Function() _compute;
  bool _dirty = true;

  @override
  T get value {
    _track();
    if (_dirty) {
      _value = _compute();
      _dirty = false;
    }
    return _value;
  }

  @override
  set value(_) => throw UnsupportedError('Cannot set value of ComputedRef');

  @override
  void _trigger() {
    _dirty = true;
    super._trigger();
  }
}

ComputedRef<T> computed<T>(T Function() compute) => ComputedRef<T>(compute);

T untracked<T>(T Function() compute) {
  final prevEffect = _activeEffect;
  _activeEffect = null;
  try {
    return compute();
  } finally {
    _activeEffect = prevEffect;
  }
}

bool _isBatching = false;
final Set<Effect> _batchedEffects = {};

void batch(void Function() fn) {
  if (_isBatching) {
    fn();
    return;
  }

  _isBatching = true;
  try {
    fn();
  } finally {
    _isBatching = false;
    for (final effect in _batchedEffects) {
      effect.run();
    }
    _batchedEffects.clear();
  }
}

class Effect {
  Effect(this._fn);

  final void Function() _fn;
  bool _active = true;
  final deps = <Ref>{};

  void run() {
    if (!_active) return;

    deps.clear();
    final prevEffect = _activeEffect;
    _activeEffect = this;
    try {
      _fn();
    } finally {
      _activeEffect = prevEffect;
    }
  }

  void stop() {
    if (_active) {
      _active = false;
      for (final dep in deps) {
        dep._deps.remove(this);
      }
      deps.clear();
    }
  }
}

void Function() effect(void Function() fn) {
  final _effect = Effect(fn);
  _effect.run();
  return _effect.stop;
}

void main() {
  final count = ref(0);
  final double = computed(() => count.value * 2);

  effect(() {
    print('Count: ${count.value}, Double: ${double.value}');
  });

  print('Setting count to 1');
  count.value = 1;

  print('Setting count to 2');
  count.value = 2;

  print('Batch update');
  batch(() {
    count.value = 3;
    count.value = 4;
  });

  final untrackedValue = untracked(() => count.value * 3);
  print('Untracked value: $untrackedValue');

  print('Setting count to 5');
  count.value = 5;

  print('Final state - Count: ${count.value}, Double: ${double.value}');
}
