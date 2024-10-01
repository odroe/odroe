import 'dart:async';

EffectImpl? _activeEffect;
final Set<void Function()> _pendingEffects = {};
bool _isFlushing = false;

class Ref<T> {
  T _value;
  final Set<EffectImpl> _effects = {};

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
      _effects.add(_activeEffect!);
    }
  }

  void _triggerEffects() {
    for (final effect in _effects) {
      if (effect.scheduler != null) {
        effect.scheduler!(effect.run);
      } else {
        _queueJob(effect.run);
      }
    }
  }
}

Ref<T> ref<T>(T value) => Ref<T>(value);

class EffectImpl {
  final void Function() fn;
  final void Function(void Function())? scheduler;

  EffectImpl(this.fn, {this.scheduler});

  void run() {
    _activeEffect = this;
    fn();
    _activeEffect = null;
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

  // 使用默认调度器（批处理）
  effect(() {
    print('Effect 1 - Count: ${count.value}, Double: ${double.value}');
  });

  // 使用自定义同步调度器
  effect(
    () {
      print('Effect 2 - Count: ${count.value}');
    },
    scheduler: (run) => run(),
  );

  count.value = 1;
  count.value = 2;
  double.value = 4;
}
