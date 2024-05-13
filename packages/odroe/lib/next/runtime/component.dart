import 'element.dart';

abstract interface class Component<Props> {
  String? displayName;

  Element call(covariant Props props) {
    throw UnimplementedError();
  }
}

extension ComponentWithoutProps on Component<void> {
  Element get zero => call(null);
}
