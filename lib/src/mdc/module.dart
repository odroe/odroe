import '../app/key.dart';
import '../app/module.dart';
import '../app/registry.dart';
import 'component.dart';
import 'parser.dart';

/// The application context key used to read the registered [MdcParser].
const mdcParserKey = ContextKey<MdcParser>('mdcParser');

/// Installs MDC parsing and renderer-specific components into an application.
final class MdcModule extends Module {
  /// Creates an MDC module.
  const MdcModule({
    this.parser = const MdcParser(),
    this.components = const <MdcComponentBinding>[],
  });

  /// The parser shared by the application.
  final MdcParser parser;

  /// Components contributed to MDC renderers.
  final List<MdcComponentBinding> components;

  @override
  void register(ModuleRegistry registry) {
    final identities = <(Type, String)>{
      for (final component in registry.bindings<MdcComponentBinding>())
        (component.rendererType, component.name),
    };
    for (final component in components) {
      if (component.name.isEmpty) {
        throw ArgumentError.value(
          component.name,
          'components',
          'An MDC component name cannot be empty.',
        );
      }
      final identity = (component.rendererType, component.name);
      if (!identities.add(identity)) {
        throw StateError(
          'MDC component "${component.name}" is already registered for '
          '${component.rendererType}.',
        );
      }
    }

    registry.provide(mdcParserKey, parser);
    for (final component in components) {
      registry.bind(component);
    }
  }
}
