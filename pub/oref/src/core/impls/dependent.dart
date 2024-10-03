import '../types/private.dart' as private;
import 'global_version.dart';

class Dependent implements private.Dependent {
  Dependent([this.derived]) : version = 0;

  @override
  int version;

  @override
  final private.Derived? derived;

  @override
  late final List<private.Node> subscribers;

  @override
  void notify() {
    // TODO: implement notify
  }

  @override
  private.Node? track() {
    // TODO: implement track
    throw UnimplementedError();
  }

  @override
  void trigger() {
    version++;
    globalVersion++;
    notify();
  }
}
