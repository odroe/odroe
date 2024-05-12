import 'package:meta/meta.dart';

import 'batch.dart';
import 'effect.dart';
import 'types.dart';

Target? evalContext;
Effect? batchedEffect;
int batchDepth = 0;
int batchIteration = 0;
int globalVersion = 0;

/// Signal flags.
@immutable
extension type const Flag._(int _) implements int {
  static const running = Flag._(1 << 0);
  static const notified = Flag._(1 << 1);
  static const outdated = Flag._(1 << 2);
  static const disposed = Flag._(1 << 3);
  static const hasError = Flag._(1 << 4);
  static const tracking = Flag._(1 << 5);
}

abstract mixin class Target {
  Node? sources;
  abstract int flags;

  void notify();
}

class Node {
  Node(this.source, this.target, [this.version = 0]);

  SignalSource source;
  Node? prevSourceNode;
  Node? nextSourceNode;

  Target target; // Computed | Effect
  Node? prevTargetNode;
  Node? nextTargetNode;

  int version;
  Node? rollbackNode;
}

class SignalSource<T> extends Signal<T>
    implements WriteableSignal<T>, ReadonlySignal<T> {
  SignalSource([this.raw]) : version = 0;

  /// Signal value
  late dynamic raw;

  /// Version numbers should always be >= 0, because the special value -1
  /// is used.
  int version;

  Node? node;
  Node? targets;

  // The signal is always true, other subtypes need to be rewritten.
  bool refresh() => true;

  void subscribe(Node node) {
    if (targets != node && node.prevTargetNode == null) {
      node.nextTargetNode = targets;
      if (targets != null) {
        targets!.prevTargetNode = node;
      }
      targets = node;
    }
  }

  void unsubscribe(Node node) {
    if (targets == null) return;

    final prev = node.prevSourceNode;
    final next = node.nextTargetNode;
    if (prev != null) {
      prev.nextTargetNode = next;
      node.prevTargetNode = null;
    }

    if (next != null) {
      next.prevTargetNode = prev;
      node.nextTargetNode = null;
    }

    if (node == targets) {
      targets = next;
    }
  }

  @override
  T peek() {
    final prevContext = evalContext;
    evalContext = null;
    try {
      return value;
    } finally {
      evalContext = prevContext;
    }
  }

  @override
  T get value {
    final node = addDependency(this);
    if (node != null) {
      node.version = version;
    }

    return raw as T;
  }

  @override
  set value(T value) {
    if (value != raw) {
      if (batchIteration > 100) {
        throw Exception('Cycle detected');
      }

      raw = value;
      version++;
      globalVersion++;

      beginBatch();
      try {
        for (Node? node = targets; node != null; node = node.nextTargetNode) {
          node.target.notify();
        }
      } finally {
        endBatch();
      }
    }
  }
}

Node? addDependency(SignalSource source) {
  if (evalContext == null) return null;

  Node? node = source.node;
  if (node == null || node.target != evalContext) {
    /**
     * `signal` is a new dependency. Create a new dependency node, and set it
     * as the tail of the current context's dependency list. e.g:
     *
     * { A <-> B       }
     *         ↑     ↑
     *        tail  node (new)
     *               ↓
     * { A <-> B <-> C }
     *               ↑
     *              tail (evalContext.sources)
     */
    node = Node(source, evalContext!)
      ..prevSourceNode = evalContext?.sources
      ..rollbackNode = node;

    if (evalContext!.sources != null) {
      evalContext!.sources!.nextSourceNode = node;
    }

    evalContext!.sources = node;
    source.node = node;

    // Subscribe to change notifications from this dependency if we're in an effect
    // OR evaluating a computed signal that in turn has subscribers.
    if ((evalContext!.flags & Flag.tracking) > 0) {
      source.subscribe(node);
    }

    return node;
  } else if (node.version == -1) {
    // `signal` is an existing dependency from a previous evaluation. Reuse it.
    node.version = 0;

    /**
     * If `node` is not already the current tail of the dependency list (i.e.
     * there is a next node in the list), then make the `node` the new tail. e.g:
     *
     * { A <-> B <-> C <-> D }
     *         ↑           ↑
     *        node   ┌─── tail (evalContext.sources)
     *         └─────│─────┐
     *               ↓     ↓
     * { A <-> C <-> D <-> B }
     *                     ↑
     *                    tail (evalContext.sources)
     */
    if (node.nextSourceNode != null) {
      node.nextSourceNode!.prevSourceNode = node.prevSourceNode;

      if (node.prevSourceNode != null) {
        node.prevSourceNode!.nextSourceNode = node.nextSourceNode;
      }

      node.prevSourceNode = evalContext!.sources;
      node.nextSourceNode = null;

      evalContext!.sources!.nextSourceNode = node;
      evalContext!.sources = node;
    }

    // We can assume that the currently evaluated effect / computed signal is already
    // subscribed to change notifications from `signal` if needed.
    return node;
  }
  return null;
}

bool needsToRecompute(Target target) {
  // Check the dependencies for changed values. The dependency list is already
  // in order of use. Therefore if multiple dependencies have changed values, only
  // the first used dependency is re-evaluated at this point.
  for (Node? node = target.sources; node != null; node = node.nextSourceNode) {
    // If there's a new version of the dependency before or after refreshing,
    // or the dependency has something blocking it from refreshing at all (e.g. a
    // dependency cycle), then we need to recompute.
    if (node.source.version != node.version ||
        !node.source.refresh() ||
        node.source.version != node.version) {
      return true;
    }
  }
  // If none of the dependencies have changed values since last recompute then
  // there's no need to recompute.
  return false;
}

void prepareSources(Target target) {
  /**
   * 1. Mark all current sources as re-usable nodes (version: -1)
   * 2. Set a rollback node if the current node is being used in a different context
   * 3. Point 'target.sources' to the tail of the doubly-linked list, e.g:
   *
   *    { undefined <- A <-> B <-> C -> undefined }
   *                   ↑           ↑
   *                   │           └──────┐
   * target.sources = A; (node is head)  │
   *                   ↓                  │
   * target.sources = C; (node is tail) ─┘
   */
  for (Node? node = target.sources; node != null; node = node.nextSourceNode) {
    final rollbackNode = node.source.node;
    if (rollbackNode != null) {
      node.rollbackNode = rollbackNode;
    }
    node.source.node = node;
    node.version = -1;

    if (node.nextSourceNode == null) {
      target.sources = node;
      break;
    }
  }
}

void cleanupSources(Target target) {
  Node? node = target.sources;
  Node? head;

  /**
   * At this point 'target.sources' points to the tail of the doubly-linked list.
   * It contains all existing sources + new sources in order of use.
   * Iterate backwards until we find the head node while dropping old dependencies.
   */
  while (node != null) {
    final prev = node.prevSourceNode;

    /**
     * The node was not re-used, unsubscribe from its change notifications and remove itself
     * from the doubly-linked list. e.g:
     *
     * { A <-> B <-> C }
     *         ↓
     *    { A <-> C }
     */
    if (node.version == -1) {
      node.source.unsubscribe(node);

      if (prev != null) {
        prev.nextSourceNode = node.nextSourceNode;
      }
      if (node.nextSourceNode != null) {
        node.nextSourceNode?.prevSourceNode = prev;
      }
    } else {
      /**
       * The new head is the last node seen which wasn't removed/unsubscribed
       * from the doubly-linked list. e.g:
       *
       * { A <-> B <-> C }
       *   ↑     ↑     ↑
       *   │     │     └ head = node
       *   │     └ head = node
       *   └ head = node
       */
      head = node;
    }

    node.source.node = node.rollbackNode;
    if (node.rollbackNode != null) {
      node.rollbackNode = null;
    }

    node = prev;
  }

  target.sources = head;
}
