import '_internal.dart';
import 'types.dart';

/// Create a new signal.
WriteableSignal<T> signal<T>([T? value]) => SignalSource(value);
