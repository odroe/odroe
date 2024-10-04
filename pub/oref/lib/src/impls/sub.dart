import '../types/private.dart' as private;
import 'link.dart' as impl;
import 'derived.dart' as impl;

void prepareDeps(private.Sub sub) {
  for (var link = sub.deps; link != null; link = link.nextDep) {
    link.version = -1;
    link.prevActiveLink = link.dep.activeLink;
    link.dep.activeLink = link;
  }
}

void cleanupDeps(private.Sub sub) {
  private.Link? head, tail = sub.depsTail, link = tail;

  while (link != null) {
    final prev = link.prevDep;
    if (link.version == -1) {
      if (link == tail) tail = prev;

      impl.removeSub(link);
      impl.removeDep(link);
    } else {
      head = link;
    }

    // Resotre previous active link.
    link.dep.activeLink = link.prevActiveLink;
    link.prevActiveLink = null;
    link = prev;
  }

  sub.deps = head;
  sub.depsTail = tail;
}

bool isDirty(private.Sub sub) {
  for (var link = sub.deps; link != null; link = link.nextDep) {
    if (link.dep.version != link.version) {
      return true;
    }

    final derived = link.dep.derived;
    if (derived != null) {
      impl.refreshDerived(derived);
      if (link.dep.version != link.version) {
        return true;
      }
    }
  }

  return false;
}
