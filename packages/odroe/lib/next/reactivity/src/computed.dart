import '_internal.dart';
import 'flags.dart';
import 'signal.dart';

final class Computed<T> extends SignalSource<T>
    with Target
    implements ReadonlySignal<T> {
  Computed(this._fn) : flags = Flag.outdated {
    _globalVersion = globalVersion - 1;
  }

  final T Function() _fn;

  late int _globalVersion;

  @override
  void notify() {
    if ((flags & Flag.notified) == 0) {
      this.flags |= Flag.outdated | Flag.notified;

      for (Node? node = targets; node != null; node = node.nextTargetNode) {
        node.target.notify();
      }
    }
  }

  @override
  T get value {
    if ((flags & Flag.running) > 0) {
      throw Exception('Cycle detected');
    }
    final node = addDependency(this);
    this.refresh();
    if (node != null) {
      node.version = version;
    }
    if ((flags & Flag.hasError) > 0) {
      throw raw as dynamic;
    }
    return raw;
  }

  @override
  bool refresh() {
    this.flags &= ~Flag.notified;

    if ((flags & Flag.running) > 0) {
      return false;
    }

    // If this computed signal has subscribed to updates from its dependencies
    // (Flag.tracking flag set) and none of them have notified about changes (Flag.outdated
    // flag not set), then the computed value can't have changed.
    if ((this.flags & (Flag.outdated | Flag.tracking)) == Flag.tracking) {
      return true;
    }
    this.flags &= ~Flag.outdated;

    if (this._globalVersion == globalVersion) {
      return true;
    }
    this._globalVersion = globalVersion;

    // Mark this computed signal running before checking the dependencies for value
    // changes, so that the Flag.running flag can be used to notice cyclical dependencies.
    this.flags |= Flag.running;
    if (version > 0 && !needsToRecompute(this)) {
      this.flags &= ~Flag.running;
      return true;
    }

    final prevContext = evalContext;
    try {
      prepareSources(this);
      evalContext = this;
      final value = _fn();
      if ((this.flags & Flag.hasError) > 0 || raw != value || version == 0) {
        raw = value;
        flags &= ~Flag.hasError;
        version++;
      }
    } catch (err) {
      raw = err;
      flags |= Flag.hasError;
      version++;
    }

    evalContext = prevContext;
    cleanupSources(this);
    this.flags &= ~Flag.running;
    return true;
  }

  @override
  void subscribe(Node node) {
    if (targets == null) {
      this.flags |= Flag.outdated | Flag.tracking;

      // A computed signal subscribes lazily to its dependencies when it
      // gets its first subscriber.
      for (Node? node = sources; node != null; node = node.nextSourceNode) {
        node.source.subscribe(node);
      }
    }

    super.subscribe(node);
  }

  @override
  void unsubscribe(Node node) {
    // Only run the unsubscribe step if the computed signal has any subscribers.
    if (targets != null) {
      super.unsubscribe(node);

      // Computed signal unsubscribes from its dependencies when it loses its last subscriber.
      // This makes it possible for unreferences subgraphs of computed signals to get garbage collected.
      if (targets == null) {
        this.flags &= ~Flag.tracking;

        for (Node? node = sources; node != null; node = node.nextSourceNode) {
          node.source.unsubscribe(node);
        }
      }
    }
  }

  @override
  int flags;
}

/// Create a new signal that is computed based on the values of other signals.
///
/// The returned computed signal is read-only, and its value is automatically
/// updated when any signals accessed from within the callback function change.
///
ReadonlySignal<T> computed<T>(T Function() fn) {
  return Computed(fn);
}
