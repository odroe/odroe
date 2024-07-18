import '../scope.dart';

class Injectable {
  const Injectable({this.scope = Scope.single, this.constructor = ''});

  final Scope scope;
  final String constructor;
}
