EffectImpl? _activeEffect;
final Set<void Function()> _pendingEffects = {};
bool _isFlushing = false;

class Ref<T> {
  T _value;
  final Set<EffectImpl> _deps = {};

  Ref(this._value);

  T get value {
    _trackEffect();
    return _value;
  }

  set value(T newValue) {
    if (newValue != _value) {
      _value = newValue;
      _triggerEffects();
    }
  }

  void _trackEffect() {
    if (_activeEffect != null) {
      _deps.add(_activeEffect!);
    }
  }

  void _triggerEffects() {
    for (final effect in _deps.toList()) {
      if (effect is ComputedImpl) {
        effect._triggerEffect();
      } else if (effect.scheduler != null) {
        effect.scheduler!(effect.run);
      } else {
        _queueJob(effect.run);
      }
    }
  }
}

Ref<T> ref<T>(T value) => Ref<T>(value);

class ComputedImpl<T> extends EffectImpl {
  final T Function() _getter;
  T? _value;
  bool _dirty = true;

  ComputedImpl(this._getter) : super(() {}) {
    fn = () {
      if (_dirty) {
        _value = _getter();
        _dirty = false;
      }
    };
  }

  T get value {
    _trackEffect();
    if (_dirty) {
      run();
    }
    return _value as T;
  }

  void _triggerEffect() {
    _dirty = true;
    _triggerEffects();
  }

  void _triggerEffects() {
    for (final effect in _deps.toList()) {
      if (effect.scheduler != null) {
        effect.scheduler!(effect.run);
      } else {
        _queueJob(effect.run);
      }
    }
  }
}

class ComputedRef<T> extends Ref<T> {
  final ComputedImpl<T> _computedImpl;

  ComputedRef(this._computedImpl) : super(_computedImpl.value);

  @override
  T get value => _computedImpl.value;

  @override
  void _trackEffect() {
    _computedImpl._trackEffect();
  }

  @override
  void _triggerEffects() {
    _computedImpl._triggerEffect();
  }
}

Ref<T> computed<T>(T Function() getter) {
  final computedImpl = ComputedImpl(getter);
  return ComputedRef(computedImpl);
}

class EffectImpl {
  void Function() fn;
  final void Function(void Function())? scheduler;
  final Set<EffectImpl> _deps = {};

  EffectImpl(this.fn, {this.scheduler});

  void run() {
    _deps.clear(); // 清除旧的依赖
    final prevEffect = _activeEffect;
    _activeEffect = this;
    fn();
    _activeEffect = prevEffect;
  }

  void _trackEffect() {
    if (_activeEffect != null && _activeEffect != this) {
      _deps.add(_activeEffect!);
    }
  }
}

void effect(
  void Function() fn, {
  void Function(void Function())? scheduler,
}) {
  final effectImpl = EffectImpl(fn, scheduler: scheduler);
  effectImpl.run();
}

void _queueJob(void Function() job) {
  _pendingEffects.add(job);
  _flushJobs();
}

void _flushJobs() {
  if (!_isFlushing) {
    _isFlushing = true;
    Future.microtask(() {
      try {
        for (final job in _pendingEffects) {
          job();
        }
      } finally {
        _isFlushing = false;
        _pendingEffects.clear();
      }
    });
  }
}

void main() {
  final count = ref(0);
  final double = ref(0);
  final sum = computed(() => count.value + double.value);

  effect(() {
    print('Sum: ${sum.value}');
  });

  count.value = 1;
  double.value = 2;
  count.value = 3;

  // 使用默认调度器（批处理）
  effect(() {
    print(
        'Effect 1 - Count: ${count.value}, Double: ${double.value}, Sum: ${sum.value}');
  });

  // 使用自定义同步调度器
  effect(
    () {
      print('Effect 2 - Count: ${count.value}');
    },
    scheduler: (run) => run(),
  );

  count.value = 4;
  double.value = 5;
}
