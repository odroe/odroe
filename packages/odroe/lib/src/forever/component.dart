import 'package:flutter/widgets.dart';

typedef Render = Component Function();

class Component {}

Component setup(Render Function() define) {
  throw UnimplementedError();
}

Component wrap(dynamic props) {
  return Component();
}

Component app({required Component body}) {
  return setup(() {
    return () => wrap(0);
  });
}

Component scafolid({required Component appbar, required Component body}) {
  return setup(() {
    return () => wrap(1);
  });
}

Component demo() {
  return setup(() {
    return () => app(
          body: scafolid(
            appbar: wrap('appbar'),
            body: wrap('body'),
          ),
        );
  });
}
