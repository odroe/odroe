import 'computed.dart';
import 'dependency.dart';
import 'flags.dart';
import 'subscriber.dart';

class CrossLink {
  CrossLink(this.sub, this.dep) : version = dep.version;

  final Dependency dep;
  final Subscriber sub;

  CrossLink? prevDep;
  CrossLink? nextDep;
  CrossLink? prevSub;
  CrossLink? nextSub;
  CrossLink? prevActiveSub;

  int version;
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
