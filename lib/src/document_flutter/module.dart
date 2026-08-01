import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/context.dart';
import '../app/module.dart';
import '../app/registry.dart';
import '../app_flutter/binding.dart';
import '../query/module.dart';
import '../router/load.dart';
import '../router_flutter/module.dart';
import '../router_flutter/router.dart';
import '../rpc/serializer.dart';
import 'browser.dart';
import 'browser_location.dart';
import 'handoff.dart';

/// Installs server-rendered document handoff into a Flutter application.
final class DocumentModule extends Module {
  /// Creates a document handoff module.
  ///
  /// Custom [serializer] adapters must match the server serializer used to
  /// render this application's handoff state.
  DocumentModule({Serializer? serializer})
    : handoff = Handoff(serializer: serializer);

  /// Handoff state decoded by this module.
  final Handoff handoff;

  Map<String, Object?>? _initial;
  StreamSubscription<Map<String, Object?>>? _frames;
  bool _acceptHandoff = true;

  @override
  void register(ModuleRegistry registry) {
    final initial = readBrowserHandoff();
    _initial = initial;
    if (initial != null) {
      final browserLocation = readFlutterBrowserLocation();
      final renderedLocation = _readInitialLocation(initial);
      if (browserLocation != null &&
          renderedLocation != null &&
          browserLocation != renderedLocation) {
        _initial = null;
        _acceptHandoff = false;
        routerInitialStateKey.provide(
          registry,
          RouterInitialState(
            location: browserLocation,
            loads: const <RouteLoadResult>[],
          ),
        );
      } else {
        handoff.apply(initial);
        final state = handoff.routerState;
        if (state != null) {
          routerInitialStateKey.provide(registry, state);
        }
      }
    }
    registry.bind(const _DocumentFlutterBinding());
  }

  @override
  void initialize(AppContext context) {
    final query = context.maybe(queryClientKey);
    final initial = _initial;
    if (initial != null && query != null) {
      handoff.apply(initial, query: query);
    }
    if (_acceptHandoff) {
      _frames = browserHandoffFrames().listen(
        (frame) => handoff.apply(frame, query: query),
        onError: (Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'document handoff',
            ),
          );
        },
      );
    }
  }

  @override
  Future<void> dispose(AppContext context) async {
    await _frames?.cancel();
  }
}

Uri? _readInitialLocation(Map<String, Object?> frame) {
  final data = frame['type'] == 'initial' ? frame['data'] : frame;
  if (data is! Map) return null;
  final location = data['location'];
  return location is String ? Uri.tryParse(location) : null;
}

final class _DocumentFlutterBinding extends FlutterBinding {
  const _DocumentFlutterBinding();

  @override
  Widget wrap(AppContext context, Widget child) =>
      _DocumentBoundary(child: child);
}

final class _DocumentBoundary extends StatefulWidget {
  const _DocumentBoundary({required this.child});

  final Widget child;

  @override
  State<_DocumentBoundary> createState() => _DocumentBoundaryState();
}

final class _DocumentBoundaryState extends State<_DocumentBoundary> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => hideBrowserDocument());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
