import 'component.dart';
import 'component_impl.dart';
import 'element.dart';

/// The [setup] function main param type def.
typedef Setup<Props> = Render Function(Props props);

/// The [DefineComponentWithputProps.z] function main param type def.
typedef SetupWithoutProps = Render Function();

/// Define a odroe [Component] of [Props], with [fn] creator function setup your [Component].
/// ```dart
/// final say = setup((String message) {
///     return () => Text(TextProps(props));
/// });
/// ```
///
/// Compared to Flutter Widgets, creating components using Odoe setup is simpler. Now we have taken the Counter component as an example:
/// ```dart
/// final counter = setup.z(() {
///     final count = signal(0);
///     void increment() => count.value++;
///
///     return () => TextButton(TextButtonProps(
///         text: 'Count: ${count.value}',
///         onTap: increment));
/// });
/// ```
/// **NOTE**: The `setup.z` is used to create a Component without any parameters.
Component<Props> setup<Props>(Setup<Props> fn) => ComponentImpl(fn);

/// Extension on [setup].
extension DefineComponentWithputProps on Component<Props> Function<Props>(
    Setup<Props>) {
  /// Define a without props Odroe [Component].
  ///
  /// Why do we need [z]?
  /// When we create a zero [Component] that does not require external parameter passing, we always need to define props of type `void _` in [Setup]. [z] is a syntactic sugar that helps us ignore the props parameter.
  ///
  /// ```dart
  /// final a = setup((_) => ...);      // Type is `Component<dynamic>` 😫
  /// final a = setup((void _) => ...); // Type is `Component<void>`    😄
  /// final b = setup.z(() => ...);     // Type is `Component<void>`    👍
  /// ```
  ///
  /// From the code perspective, using [z] is more concise.
  /// But this is a hobby multiple-choice question.
  Component<void> z(SetupWithoutProps fn) => this((_) => fn());
}
