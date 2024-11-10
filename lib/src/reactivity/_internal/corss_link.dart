import 'dependency.dart';
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
