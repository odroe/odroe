import 'component.dart';
import 'element.dart';

typedef Setup<Props> = Render Function(Props props);
typedef SetupWithoutProps = Render Function();

Component<Props> setup<Props>(Setup<Props> fn) {
  throw UnimplementedError();
}

extension DefineComponentWithputProps on Component<Props> Function<Props>(
    Setup<Props>) {
  Component<void> z(SetupWithoutProps fn) {
    throw UnimplementedError();
  }
}
