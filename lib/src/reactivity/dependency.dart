import 'computed.dart';
import 'corss_link.dart';
import 'effect.dart';
import 'flags.dart';
import 'global_version.dart';
import 'subscriber.dart';

class Dependency {
  Dependency([this.computed]);

  final ComputedImpl? computed;

  late int version = 0;
  late CrossLink? activeLink;
  late CrossLink? subs;
  late int subsCounter = 0;
  late final map = <Object, Dependency>{};
  late Object? key;

  CrossLink? track() {
    if (activeSub == null || !shouldTrack || activeSub == computed) {
      return null;
    }

    var link = activeLink;
    if (link == null || link.sub != activeSub) {
      link = activeLink = CrossLink(activeSub!, this);
      if (activeSub!.depsHead == null) {
        activeSub!.depsHead = activeSub!.depsTail = link;
      } else {
        link.prevDep = activeSub!.depsTail;
        activeSub!.depsTail!.nextDep = link;
        activeSub!.depsTail = link;
      }

      addSub(link);
    } else if (link.version == -1) {
      link.version = version;
      if (link.nextDep != null) {
        final next = link.nextDep!;
        next.prevDep = link.prevDep;

        link.prevDep?.nextDep = next;
        link.prevDep = activeSub!.depsTail;
        link.nextDep = null;

        activeSub!.depsTail!.nextDep = link;
        activeSub!.depsTail = link;

        if (activeSub!.depsHead == link) {
          activeSub!.depsHead = next;
        }
      }
    }

    return link;
  }

  void trigger() {
    version++;
    dumpGlobalVersion();
    notify();
  }

  void notify() {}
}

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
