import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/context.dart';
import '../app/module.dart';
import 'binding.dart';

/// Builds the Flutter application owned by an [AppContext].
typedef AppBuilder = Widget Function(AppContext context);

/// Builds a visible module initialization failure.
typedef AppErrorBuilder = Widget Function(Object error, StackTrace stackTrace);

/// Flutter composition root for an explicit list of modules.
final class App extends StatefulWidget {
  /// Creates an application that installs [modules] in declaration order.
  App({
    super.key,
    required Iterable<Module> modules,
    required this.builder,
    this.loading = const SizedBox.shrink(),
    this.errorBuilder = _defaultErrorBuilder,
  }) : modules = List<Module>.of(modules, growable: false);

  /// Modules selected by the application.
  final List<Module> modules;

  /// Builds the application after every module is initialized.
  final AppBuilder builder;

  /// Widget shown while modules initialize.
  final Widget loading;

  /// Builds initialization failures.
  final AppErrorBuilder errorBuilder;

  @override
  State<App> createState() => _AppState();
}

final class _AppState extends State<App> with WidgetsBindingObserver {
  late final Future<AppContext> _loading;
  AppContext? _context;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loading = AppContext.create(widget.modules);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final context = _context;
    if (context == null) return;
    for (final binding in context.bindings<FlutterBinding>()) {
      binding.didChangeAppLifecycleState(context, state);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppContext>(
    future: _loading,
    builder: (context, snapshot) {
      final error = snapshot.error;
      if (error != null) {
        return widget.errorBuilder(error, snapshot.stackTrace!);
      }
      final app = snapshot.data;
      if (app == null) return widget.loading;
      _context = app;
      var child = widget.builder(app);
      final bindings = app.bindings<FlutterBinding>().toList(growable: false);
      for (final binding in bindings.reversed) {
        child = binding.wrap(app, child);
      }
      return _AppContextScope(context: app, child: child);
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final context = _context;
    if (context != null) {
      unawaited(context.dispose());
    } else {
      unawaited(_loading.then((context) => context.dispose()));
    }
    super.dispose();
  }
}

final class _AppContextScope extends InheritedWidget {
  const _AppContextScope({required this.context, required super.child});

  final AppContext context;

  @override
  bool updateShouldNotify(_AppContextScope oldWidget) =>
      oldWidget.context != context;
}

/// Reads the current [AppContext] from a Flutter build context.
extension AppBuildContext on BuildContext {
  /// The application context installed by the nearest [App].
  AppContext get appContext =>
      dependOnInheritedWidgetOfExactType<_AppContextScope>()!.context;
}

Widget _defaultErrorBuilder(Object error, StackTrace stackTrace) =>
    ErrorWidget.withDetails(
      message: error.toString(),
      error: FlutterError(error.toString()),
    );
