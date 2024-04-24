import 'package:flutter/foundation.dart' show Key;

import 'compare_props.dart';

class PropsKey<T> implements Key {
  const PropsKey(this.props);
  final T props;

  @override
  int get hashCode => Object.hash(runtimeType, props);

  @override
  bool operator ==(Object other) => compareProps(props, other);
}
