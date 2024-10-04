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
}

void addSub(private.Link link) {
  if ((link.sub.flags & Flags.tracking) == 0) {
    return;
  }

  final derived = link.dep.derived;
  if (derived != null && link.dep.subs != null) {
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
