import 'computed.dart';
import 'link.dart';

/// A class representing a dependency in a reactive computation system.
class Dependency {
  /// Creates a new [Dependency] optionally associated with a [Computed] value.
  /// The version counter starts at 0.
  Dependency([this.computed]) : version = 0;

  /// The computed value this dependency is associated with, if any.
  final Computed? computed;

  /// A counter that gets incremented when the dependency changes.
  int version;

  /// The currently active subscription link, if any.
  Link? activeLink;

  /// The head of the linked list of subscriptions.
  Link? subsHead;

  /// The tail of the linked list of subscriptions.
  Link? subsTail;

  /// Counter tracking number of subscriptions.
  int subCounter = 0;

  /// Map storing nested dependencies keyed by their identifiers.
  late final map = <dynamic, Dependency>{};

  /// Key identifying this dependency in a parent dependency's map.
  dynamic key;
}
