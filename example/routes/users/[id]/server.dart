import 'package:odroe/server.dart';

get(Event event) {
  return useRequestURI(event);
}
