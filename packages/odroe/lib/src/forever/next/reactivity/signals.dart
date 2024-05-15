import 'package:signals_core/signals_core.dart' as signals;

import '../../warn.dart';

export 'package:signals_core/signals_core.dart'
    show
        SignalsError,
        SignalsReadAfterDisposeError,
        SignalsWriteAfterDisposeError;

/// The abstract interface of [Signal].This is readable interface. expose the [value] getter.
abstract interface class Readonly<T> {
  /// Returns the value by the current [Readonly] | [Signal].
  T get value;

  /// Reading [Signal] | [Readonly] without subscribing to them
  ///
  /// On the rare occasion that you need to write to a signal
  /// inside [effect], but don't want the effect to re-run
  /// when that signal changes, you can use [peek] method to get
  /// the signal's current value without subscribing.
  ///
  /// ```dart
  /// final delta = signal(0);
  /// final count = signal(0);
  ///
  /// effect(() {
  ///   // Update `count` without subscribing to `count`:
  ///   count.value = count.peek() + delta.value;
  /// });
  ///
  /// // Setting `delta` reruns the effect:
  /// delta.value = 1;
  ///
  /// // This won't rerun the effect because it didn't access `.value`:
  /// count.value = 10;
  /// ```
  ///
  /// **NOTE**: The scenarios in which you don't want to subscribe to a
  /// signal are rare. In most cases you want your effect to subscribe
  /// to all signals. Only use [peek] when you really need to.
  T peek();
}

/// Internal stringable mixin;
mixin _Stringable {
  String _toDisplayString();

  @override
  toString() => _toDisplayString();
}

/// The [Signal] expose the [value] setter and [toReadobly] method.
abstract interface class Signal<T> implements Readonly<T> {
  /// Wirte a new value to the current [Signal].
  set value(T value);
}

/// Internal [Readonly] proxy.
///
/// Why do we need a proxy? Merely type conversion is not enough to meet true read-only requirements, so using a read-only Signal proxy ensures that it cannot be converted back to the original type through `as dynamic as Signal`.
class _ReadonlyProxy<T> with _Stringable implements Readonly<T> {
  const _ReadonlyProxy(this.signal);
  final Signal<T> signal;

  @override
  T peek() => signal.peek();

  @override
  String _toDisplayString() => value.toString();

  @override
  T get value => signal.value;
}

/// Internal [Signal] proxy
class _SignalProxy<T> with _Stringable implements Signal<T> {
  const _SignalProxy(this.signal);

  final signals.Signal<T> signal;

  @override
  String _toDisplayString() => value.toString();

  @override
  T get value => signal.value;

  @override
  set value(T value) => signal.value = value;

  @override
  T peek() => signal.peek();
}

/// Creates a new signal with the given argument as its initial value:
///
/// ```dart
/// final count = signal(0);
/// ```
Signal<T> signal<T>(T initialValue,
    {bool autoDispose = false, String? debugLabel}) {
  if (isSignal(initialValue)) {
    warn(
        'The initial value is already a signal, unless you intentionally did so. But this warning message cannot be hidden because it is a very incorrect use case.');
  }

  final inner = signals.signal(initialValue,
      autoDispose: autoDispose, debugLabel: debugLabel);

  return _SignalProxy(inner);
}

/// Internal computed proxy.
class _ComputedProxy<T> with _Stringable implements Readonly<T> {
  const _ComputedProxy(this.computed);

  final signals.Computed<T> computed;

  @override
  T peek() => computed.peek();

  @override
  String _toDisplayString() => value.toString();

  @override
  T get value => computed.value;
}

/// Creates a new signal that is computed based on the values of
/// other signals. The returned computed signal is read-only, and
/// its value is automatically updated when any signals accessed
/// from within the callback function change.
Readonly<T> computed<T>(T Function() getter,
    {bool autoDispose = false, String? debugLabel}) {
  final inner = signals.computed(getter,
      autoDispose: autoDispose, debugLabel: debugLabel);

  return _ComputedProxy(inner);
}

/// To run arbitrary code in response to signal changes, we can
/// use `effect(fn)`. Similar to computed signals, effects track
/// which signals are accessed and re-run their callback when
/// those signals change. If the callback returns a function, this
/// function will be run before the next value update.
/// Unlike computed signals, `effect()` does not return a signal -
/// it's the end of a sequence of changes.
void Function() effect(Function() handler, {String? debugLabel}) {
  return signals.effect(handler, debugLabel: debugLabel);
}

/// In case when you're receiving a callback that can read some signals, but you don't want to subscribe to them, you can use [untracked] to prevent any subscriptions from happening.
///
/// ```dart
/// final counter = signal(0);
/// final effectCount = signal(0);
/// final fn = () => effectCount.value + 1;
///
/// effect(() {
/// 	print(counter.value);
///
/// 	// Whenever this effect is triggered, run `fn` that gives new value
/// 	effectCount.value = untracked(fn);
/// });
/// ```
T untracked<T>(T Function() getter) => signals.untracked(getter);

/// The batch(fn) function can be used to combine multiple value
/// updates into one "commit" at the end of the provided callback.
/// Batches can be nested and changes are only flushed once the
/// outermost batch callback completes. Accessing a signal that has
/// been modified within a batch will reflect its updated value.
///
/// ```dart
/// final name = signal('Seven');
/// final surname = signal('Du');
///
/// // Combine both writes into one update
/// batch(() {
///     name = 'Odroe';
///     surname = 'Open Source';
/// });
/// ```
T batch<T>(T Function() handler) => signals.batch(handler);

/// Determine whether an object is a [Signal] or [ReadonlySignal].
bool isSignal(value) => value is Signal || value is signals.Signal;
