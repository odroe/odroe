/// Returns the function passed as an argument without modification.
///
/// This function acts as an identity function for functions, allowing it to be
/// used in contexts where a function is expected to be transformed but should
/// remain unchanged.
///
/// # Why do we need `compose`?
///
/// When using oref's reactivity API to compose new composables, Dart's function definitions often require us
/// to explicitly specify the return type. The `compose` function helps us automatically infer the return type.
///
/// For example:
/// ```dart
/// Function useCounter(BuildContext ctx) {
///     final count = ref(ctx, 0);
///     return () => (
///         valueOf: () => count.value,
///         increment: () => count.value++,
///     );
/// }
/// ```
/// We need to return a Record with the signature `({ int Function() valueOf, void Function() increment })`. Although useCounter
/// does return this type at runtime, in the IDE the return type of useCounter would be inferred as `dynamic`.
///
/// To solve this problem, we could use the following approach:
/// ```dart
/// final useCounter = (BuildContext ctx) {
///     final count = ref(ctx, 0);
///     return (
///         valueOf: () => count.value,
///         increment: () => count.value++,
///     );
/// };
/// ```
/// But this raises a new issue: Dart lint will give a warning: `dart: Use a function declaration rather than a variable assignment to bind a function to a name.`
///
/// Therefore, the introduction of the `compose` function is to avoid this lint warning:
/// ```dart
/// final useCounter = compose((BuildContext ctx) {
///     final count = ref(ctx, 0);
///     return (
///         valueOf: () => count.value,
///         increment: () => count.value++,
///     );
/// });
/// ```
@Deprecated('Try useing inferReturnType(), remove in v0.4')
F compose<F extends Function>(F fn) => fn;
