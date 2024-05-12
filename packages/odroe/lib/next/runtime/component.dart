import 'element.dart';

abstract interface class Component<Props> {
  String? displayName;

  Element call(Props props) {
    throw UnimplementedError();
  }
}

extension ComponentWithoutProps<Props extends Object?> on Component<Props> {
  Element get zero => call(null as Props);
}
