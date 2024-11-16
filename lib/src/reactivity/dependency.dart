import 'batch.dart';
import 'computed_ref_impl.dart';
import 'corss_link.dart';
import 'global_version.dart';
import 'subscriber.dart';
import 'tracking.dart';
import 'utils.dart';

class Dependency {
  Dependency([this.computed]);

  final ComputedRefImpl? computed;

  late int version = 0;
  CrossLink? activeLink;
  CrossLink? subs;
  late int subsCounter = 0;
  late final map = <Object, Dependency>{};
  Object? key;

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
      flushBatch();
    }
  }
}
