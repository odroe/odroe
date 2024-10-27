import 'subscriber.dart';

class Link {
  Link(this.subscriber, this.dependency) : version = dependency.version;

  final Subscriber subscriber;
  final Dependency dependency;
  int version;

  Link? prevDependency;
  Link? nextDependency;
  Link? prevSubscriber;
  Link? nextSubscriber;
  Link? prevActiveLink;
}

class Dependency {
  Dependency(); // TODO Computed.

  int version = 0;
  Link? activeLink;
  Link? subscribers;
  Link? subscribersHead;
  late final Map<Object, Dependency> map = {};
  Object? key;
  int subscriberCounter = 0;
}
