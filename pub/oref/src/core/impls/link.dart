import '../types/private.dart' as private;

class Link implements private.Link {
  Link(this.sub, this.dep) : version = dep.vrsion;

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
