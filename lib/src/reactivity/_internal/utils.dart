import '../public/tracking.dart';
import 'computed_ref_impl.dart';
import 'corss_link.dart';
import 'effect_impl.dart';
import 'flags.dart';
import 'global_version.dart';
import 'subscriber.dart';

void addSub(CrossLink link) {
  link.dep.version++;

  if (link.sub.flags & Flags.tracking != 0) {
    final computed = link.dep.computed;
    if (computed != null && link.dep.subs == null) {
      computed.flags |= Flags.tracking | Flags.dirty;
      for (var link = computed.depsHead; link != null; link = link.nextDep) {
        addSub(link);
      }
    }

    final currentTail = link.dep.subs;
    if (currentTail != link) {
      link.prevSub = currentTail;
      if (currentTail != null) {
        currentTail.nextSub = link;
      }
    }

    link.dep.subs = link;
  }
}

void prepareDeps(Subscriber sub) {
  for (var link = sub.depsHead; link != null; link.nextDep) {
    link.version = -1;
    link.prevActiveSub = link.dep.activeLink;
    link.dep.activeLink = link;
  }
}

void cleanupDeps(Subscriber sub) {
  CrossLink? head, tail = sub.depsTail, link = tail;
  while (link != null) {
    final prev = link.prevDep;
    if (link.version == -1) {
      if (link == tail) tail = prev;
      removeSub(link);
      removeDep(link);
    } else {
      head = link;
    }

    link.dep.activeLink = link.prevActiveSub;
    link.prevActiveSub = null;
    link = prev;
  }

  sub.depsHead = head;
  sub.depsTail = tail;
}

void removeSub(CrossLink link, [bool soft = false]) {
  final CrossLink(:dep, :prevSub, :nextSub) = link;
  if (prevSub != null) {
    prevSub.nextSub = nextSub;
    link.prevSub = null;
  }

  if (nextSub != null) {
    nextSub.prevSub = prevSub;
    link.nextSub = null;
  }

  if (dep.subs == link) {
    dep.subs = prevSub;
    if (prevSub != null && dep.computed != null) {
      dep.computed!.flags &= ~Flags.tracking;
      for (var link = dep.computed!.depsHead;
          link != null;
          link = link.nextDep) {
        removeSub(link, true);
      }
    }
  }

  if (!soft && --dep.subsCounter == 0 && dep.map.isNotEmpty) {
    dep.map.remove(dep.key);
  }
}

void removeDep(CrossLink link) {
  final CrossLink(:prevDep, :nextDep) = link;
  if (prevDep != null) {
    prevDep.nextDep = nextDep;
    link.prevDep = null;
  }

  if (nextDep != null) {
    nextDep.prevDep = prevDep;
    link.nextDep = null;
  }
}

bool refreshComputedWith(CrossLink link) {
  if (link.dep.computed != null) {
    refreshComputed(link.dep.computed!);
  }

  return link.dep.version != link.version;
}

bool isDirty(Subscriber sub) {
  for (var link = sub.depsHead; link != null; link = link.nextDep) {
    if (link.dep.version != link.version || refreshComputedWith(link)) {
      return true;
    }
  }

  return false;
}

void refreshComputed(ComputedRefImpl computed) {
  if (computed.flags & Flags.tracking != 0 &&
      computed.flags & Flags.dirty == 0) {
    return;
  }

  computed.flags &= ~Flags.dirty;
  if (computed.version == globalVersion) {
    return;
  }

  computed.version = globalVersion;
  computed.flags |= Flags.running;

  if (computed.dep.version > 0 &&
      computed.depsHead != null &&
      !isDirty(computed)) {
    return;
  }

  final resetActiveSub = setActiveSub(computed);
  enableTracking();

  try {
    prepareDeps(computed);
    final value = computed.getter(computed.raw);
    if (computed.dep.version == 0 || !identical(computed.raw, value)) {
      computed.raw = value;
      computed.dep.version++;
    }
  } catch (e) {
    computed.dep.version++;
  } finally {
    resetActiveSub();
    resetTracking();
    cleanupDeps(computed);
    computed.flags &= ~Flags.running;
  }
}

void cleanupEffect<T>(EffectImpl<T> effect) {
  final cleanup = effect.cleanup;
  effect.cleanup = null;
  if (cleanup != null) {
    final reset = setActiveSub(null);
    try {
      cleanup();
    } finally {
      reset();
    }
  }
}
