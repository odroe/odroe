import '../types/private.dart' as private;
import 'flags.dart';

class Link implements private.Link {
  Link(this.sub, this.dep) : version = dep.version;

  @override
  int version;

  @override
  final private.Dep dep;

  @override
  final private.Sub sub;

  @override
  private.Link? nextDep;

  @override
  private.Link? nextSub;

  @override
  private.Link? prevDep;

  @override
  private.Link? prevSub;

  @override
  private.Link? prevActiveLink;
}

void addSub(private.Link link) {
  if ((link.sub.flags & Flags.tracking) == 0) {
    return;
  }

  final derived = link.dep.derived;
  if (derived != null && link.dep.subs == null) {
    derived.flags |= Flags.tracking | Flags.dirty;
    for (var link = derived.deps; link != null; link = link.nextDep) {
      addSub(link);
    }
  }

  final tail = link.dep.subs;
  if (tail != link) {
    link.prevSub = tail;
    if (tail != null) {
      tail.nextSub = link;
    }
  }

  link.dep.subs = link;
}

void removeSub(private.Link link, [bool soft = false]) {
  final dep = link.dep, prevSub = link.prevSub, nextSub = link.nextSub;
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
  }
  if (dep.subs != null && dep.derived != null) {
    dep.derived!.flags &= ~Flags.tracking;
    for (var link = dep.derived!.deps; link != null; link = link.nextDep) {
      removeSub(link, true);
    }
  }
}

void removeDep(private.Link link) {
  final prevDep = link.prevDep, nextDep = link.nextDep;
  if (prevDep != null) {
    prevDep.nextDep = nextDep;
    link.prevDep = null;
  }
  if (nextDep != null) {
    nextDep.prevDep = prevDep;
    link.nextDep = null;
  }
}
