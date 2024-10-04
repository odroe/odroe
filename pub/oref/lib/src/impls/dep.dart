import '../types/private.dart' as private;
import 'batch.dart';
import 'global.dart';
import 'link.dart' as impl;

class Dep implements private.Dep {
  Dep([this.derived]) : version = 0;

  @override
  int version;

  @override
  final private.Derived? derived;

  @override
  private.Link? activeLink;

  @override
  private.Link? subs;

  @override
  void notify() {
    startBatch();
    try {
      for (private.Link? link = subs; link != null; link = link.prevSub) {
        link.sub.notify()?.dep.notify();
      }
    } finally {
      endBatch();
    }
  }

  @override
  private.Link? track() {
    if (activeSub == null || !shouldTrack || activeSub == derived) {
      return null;
    }

    private.Link? link = activeLink;
    if (link == null || link.sub != activeSub) {
      link = activeLink = impl.Link(activeSub!, this);

      if (activeSub!.deps == null) {
        activeSub!.deps = activeSub!.depsTail = link;
      } else {
        link.prevDep = activeSub!.depsTail;
        activeSub!.depsTail!.nextDep = link;
        activeSub!.depsTail = link;
      }

      impl.addSub(link);
    } else if (link.version == -1) {
      link.version = version;
      if (link.nextDep != null) {
        final next = link.nextDep!;
        next.prevDep = link.prevDep;
        if (link.prevDep != null) {
          link.prevDep!.nextDep = next;
        }

        link.prevDep = activeSub!.depsTail;
        link.nextDep = null;
        activeSub!.depsTail!.nextDep = link;
        activeSub!.depsTail = link;

        if (activeSub!.deps == link) {
          activeSub!.deps = next;
        }
      }
    }

    return link;
  }

  @override
  void trigger() {
    version++;
    globalVersion++;
    notify();
  }
}
