import 'dependency.dart';
import 'subscriber.dart';

/// A Link represents a connection between a [Subscriber] and a [Dependency],
/// maintaining bidirectional links to form a doubly-linked list structure.
class Link {
  /// Creates a new Link connecting a [Subscriber] and [Dependency].
  ///
  /// The version is initialized from the dependency's version.
  Link(this.sub, this.dep) : version = dep.version;

  /// The subscriber associated with this link.
  final Subscriber sub;

  /// The dependency associated with this link.
  final Dependency dep;

  /// The version number of the dependency at the time the link was created.
  int version;

  /// Link to the previous dependency in the linked list.
  Link? prevDep;

  /// Link to the next dependency in the linked list.
  Link? nextDep;

  /// Link to the previous subscriber in the linked list.
  Link? prevSub;

  /// Link to the next subscriber in the linked list.
  Link? nextSub;

  /// Reference to the previous active link in a sequence.
  Link? prevActiveLink;
}
