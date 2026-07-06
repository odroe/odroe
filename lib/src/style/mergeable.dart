/// A value that can merge another value of the same type into itself.
///
/// Implement this for partial declarations whose non-null members can be
/// overlaid by a later declaration of the same shape.
abstract interface class Mergeable<T> {
  /// Returns the result of applying [later] over this value.
  T merge(T later);
}

/// Merging support for optional declaration slots.
extension MergeableNullable<T extends Mergeable<T>> on T? {
  /// Returns the merged result of this value and [later].
  ///
  /// When both values are present, [later] is merged over this value. When only
  /// one side is present, that side is returned unchanged.
  T? mergedWith(T? later) {
    return switch ((this, later)) {
      (final current?, final next?) => current.merge(next),
      (final current?, null) => current,
      (null, final next?) => next,
      _ => null,
    };
  }
}
