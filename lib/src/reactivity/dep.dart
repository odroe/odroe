import 'effect.dart';

int globalVersion = 0;

class Link {
  Link(this.sub, this.dep) : version = dep.version;

  final Subscriber sub;
  final Dep dep;

  int version;
  Link? nextDep;
  Link? prevDep;
  Link? nextSub;
  Link? prevSub;
  Link? prevActiveLink;
}

class Dep {
  Dep([this.computed]);

  final ComputedRefImpl? computed;

  var version = 0;
  Link? activeLink;
  Link? subs;
  int sc = 0;

  Link? track() {
    if (activeSub == null || !shouldTrack || activeSub == computed) {
      return null;
    }

    var link = activeLink;
    if (link == null || link.sub != activeSub) {
      link = activeLink = Link(activeSub, this);

      if (activeSub.deps == null) {
        activeSub.deps = activeSub.depsTail = link;
      } else {
        link.prevDep = activeSub.depsTail;
        activeSub.depsTail!.nextDep = link;
        activeSub.depsTail = link;
      }

      _addSub(link);
    } else if (link.version == -1) {
      link.version = version;

      if (link.nextDep != null) {
        final next = link.nextDep!;
        next.prevDep = link.prevDep;
        if (link.prevDep != null) {
          link.prevDep!.nextDep = next;
        }

        link.prevDep = activeSub.depsTail;
        link.nextDep = null;
        activeSub.depsTail!.nextDep = link;
        activeSub.depsTail = link;

        if (activeSub.deps == link) {
          activeSub.deps = next;
        }
      }
    }

    return link;
  }

  void trigger() {
    version++;
    globalVersion++;
    notify();
  }

  void notify() {
    startBatch();
    try {
      for (var link = subs; link != null; link = link.prevSub) {
        link.sub.notify();
        if (link.sub is ComputedRefImpl) {
          (link.sub as ComputedRefImpl).dep.notify();
        }
      }
    } finally {
      endBatch();
    }
  }
}

void _addSub(Link link) {
  link.dep.sc++;
  if (link.sub.flags & EffectFlags.tracking != 0) {
    final computed = link.dep.computed;
    if (computed != null && link.dep.subs != null) {
      computed.flags |= EffectFlags.tracking | EffectFlags.dirty;
      for (var link = computed.deps; link != null; link = link.nextDep) {
        _addSub(link);
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
