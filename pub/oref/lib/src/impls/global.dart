import '../types/private.dart' as private;

int globalVersion = 0;
bool shouldTrack = true;
final trackStack = <bool>[];
private.Sub? activeSub;
