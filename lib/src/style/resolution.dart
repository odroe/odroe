import 'appearance.dart';
import 'axis.dart';
import 'binding.dart';
import 'color.dart';
import 'condition.dart';
import 'contract.dart';
import 'diagnostic.dart';
import 'dimension.dart';
import 'identifier.dart';
import 'state.dart';
import 'style.dart';

/// The result of resolving a [Style] against one binding and condition set.
///
/// Resolution stays inside the Odroe core model. The [appearance] contains
/// concrete style values, not CSS declarations, Flutter widgets, Material theme
/// objects, DOM nodes, or platform adapter output.
///
/// Diagnostics describe resolution-time problems such as a term that the
/// selected binding does not provide. They do not throw, so tools can show a
/// partial resolved value alongside every issue found in one pass.
final class StyleResolution {
  /// Creates a style resolution result.
  StyleResolution({
    required this.appearance,
    Iterable<Diagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics);

  /// The resolved platform-neutral appearance.
  final ResolvedAppearance appearance;

  /// Resolution diagnostics collected while producing [appearance].
  final List<Diagnostic> diagnostics;

  /// Whether resolution completed without diagnostics.
  bool get isValid => diagnostics.isEmpty;
}

/// A resolved platform-neutral appearance.
///
/// This is the concrete counterpart to [Appearance]. Term-backed properties
/// have been looked up through a selected [Binding], and literal properties have
/// been unwrapped into direct Dart values.
final class ResolvedAppearance {
  /// Creates a resolved appearance from optional visual facets.
  const ResolvedAppearance({this.surface, this.content, this.metrics});

  /// Resolved surface-facing visual values.
  final ResolvedSurface? surface;

  /// Resolved content-facing visual values.
  final ResolvedContent? content;

  /// Resolved size and spacing values.
  final ResolvedMetrics? metrics;
}

/// Resolved surface-facing visual values.
final class ResolvedSurface {
  /// Creates a resolved surface declaration.
  const ResolvedSurface({this.fill, this.stroke, this.radius, this.elevation});

  /// The resolved surface fill color.
  final Color? fill;

  /// The resolved stroke or border color.
  final Color? stroke;

  /// The resolved corner or shape radius.
  final Dimension? radius;

  /// The resolved platform-neutral elevation amount or role.
  final Dimension? elevation;
}

/// Resolved content-facing visual values.
final class ResolvedContent {
  /// Creates a resolved content declaration.
  const ResolvedContent({this.color, this.text, this.icon, this.opacity});

  /// The resolved foreground color.
  final Color? color;

  /// The resolved semantic text role.
  final Identifier? text;

  /// The resolved semantic icon role.
  final Identifier? icon;

  /// The resolved content opacity.
  final double? opacity;
}

/// Resolved platform-neutral spacing and size values.
final class ResolvedMetrics {
  /// Creates a resolved metrics declaration.
  const ResolvedMetrics({
    this.padding,
    this.gap,
    this.width,
    this.height,
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
  });

  /// The resolved content padding.
  final ResolvedInsets? padding;

  /// The resolved space between repeated children.
  final Dimension? gap;

  /// The resolved preferred width.
  final Dimension? width;

  /// The resolved preferred height.
  final Dimension? height;

  /// The resolved minimum width.
  final Dimension? minWidth;

  /// The resolved minimum height.
  final Dimension? minHeight;

  /// The resolved maximum width.
  final Dimension? maxWidth;

  /// The resolved maximum height.
  final Dimension? maxHeight;
}

/// Resolved four-sided spacing.
final class ResolvedInsets {
  /// Creates resolved insets from explicit sides.
  const ResolvedInsets({this.top, this.right, this.bottom, this.left});

  /// The resolved top inset.
  final Dimension? top;

  /// The resolved right inset.
  final Dimension? right;

  /// The resolved bottom inset.
  final Dimension? bottom;

  /// The resolved left inset.
  final Dimension? left;
}

/// Resolves a [Style] into concrete core values.
extension StyleResolver<P> on Style<P> {
  /// Resolves this style with [binding] and the active style inputs.
  ///
  /// Merge order is fixed and deterministic:
  ///
  /// * root appearance;
  /// * selected [part] appearance, when present;
  /// * matching cases in declaration order;
  /// * [instanceOverride], when provided.
  ///
  /// Terms are resolved only after the final appearance has been merged. This
  /// means a later literal override can replace an earlier term reference
  /// without requiring that earlier term to exist in the selected binding.
  ///
  /// ```dart
  /// final resolved = button.resolve(
  ///   binding: light,
  ///   part: ButtonPart.icon,
  ///   states: [state.hovered],
  ///   axisValues: [tone(ButtonTone.danger)],
  /// );
  /// ```
  StyleResolution resolve({
    required Binding binding,
    P? part,
    Iterable<State> states = const [],
    Iterable<AxisCondition<Object?>> axisValues = const [],
    Appearance? instanceOverride,
  }) {
    final state = _ResolutionState(
      binding: binding,
      contract: contract,
      states: states,
      axisValues: axisValues,
      styleId: id,
    );
    var appearance = root;

    if (part != null) {
      if (contract != null && !contract!.allowsPart(part)) {
        state.report(
          Diagnostic(
            code: DiagnosticCodes.styleUnknownPart,
            target: DiagnosticTarget(kind: 'style', name: id.value),
            message:
                'Style `${id.value}` resolves part `$part`, but that part is '
                'not present in its contract.',
          ),
        );
      }

      final partAppearance = parts[part];
      if (partAppearance != null) {
        appearance = appearance.merge(partAppearance);
      }
    }

    for (final styleCase in cases) {
      if (state.matches(styleCase.when)) {
        appearance = appearance.merge(styleCase.appearance);
      }
    }

    if (instanceOverride != null) {
      appearance = appearance.merge(instanceOverride);
    }

    return StyleResolution(
      appearance: state.resolveAppearance(appearance),
      diagnostics: state.diagnostics,
    );
  }
}

final class _ResolutionState {
  _ResolutionState({
    required Binding binding,
    required this.contract,
    required Iterable<State> states,
    required Iterable<AxisCondition<Object?>> axisValues,
    required this.styleId,
  }) : _states = Set.unmodifiable(states),
       _axisValues = Map.unmodifiable({
         for (final value in axisValues) value.axis.id.value: value,
       }),
       _assignments = _assignmentsById(binding.assignments);

  final Contract<Object?>? contract;
  final Set<State> _states;
  final Map<String, AxisCondition<Object?>> _axisValues;
  final Map<String, Assignment<Object?>> _assignments;
  final Identifier styleId;
  final List<Diagnostic> diagnostics = [];

  void report(Diagnostic diagnostic) {
    diagnostics.add(diagnostic);
  }

  bool matches(Condition condition) {
    final result = _matches(condition);
    return result.isValid && result.matches;
  }

  _ConditionMatch _matches(Condition condition) {
    switch (condition) {
      case State(:final id):
        if (contract != null && !contract!.allowsState(condition)) {
          report(
            Diagnostic(
              code: DiagnosticCodes.styleUnknownState,
              target: DiagnosticTarget(kind: 'style', name: styleId.value),
              message:
                  'Style `${styleId.value}` uses state `${id.value}` that is '
                  'not present in its contract.',
            ),
          );
          return const _ConditionMatch.invalid();
        }

        return _ConditionMatch(matches: _states.contains(condition));
      case AxisCondition<Object?>(:final axis, :final value):
        final declaredAxis = contract?.axisNamed(axis.id);
        if (contract != null && declaredAxis == null) {
          report(
            Diagnostic(
              code: DiagnosticCodes.styleUnknownAxis,
              target: DiagnosticTarget(kind: 'style', name: styleId.value),
              message:
                  'Style `${styleId.value}` uses axis `${axis.id.value}` that '
                  'is not present in its contract.',
            ),
          );
          return const _ConditionMatch.invalid();
        }

        if (declaredAxis != null &&
            (!declaredAxis.acceptsContract(axis) ||
                !declaredAxis.acceptsValue(value))) {
          report(
            Diagnostic(
              code: DiagnosticCodes.styleInvalidAxisValueType,
              target: DiagnosticTarget(kind: 'axis', name: axis.id.value),
              message:
                  'Style `${styleId.value}` uses a ${value.runtimeType} value '
                  'for axis `${axis.id.value}`, but its contract declares that '
                  'axis as ${declaredAxis.valueType}.',
            ),
          );
          return const _ConditionMatch.invalid();
        }

        final hasActiveValue = _axisValues.containsKey(axis.id.value);
        final active = _axisValues[axis.id.value];
        final activeAxis = hasActiveValue ? active!.axis : declaredAxis ?? axis;
        final Object? activeValue;
        if (hasActiveValue) {
          activeValue = active!.value;
        } else if (declaredAxis != null) {
          activeValue = declaredAxis.defaultValue;
        } else {
          activeValue = axis.defaultValue;
        }
        return _ConditionMatch(
          matches: axis.acceptsContract(activeAxis) && activeValue == value,
        );
      case AllCondition(:final conditions):
        var isValid = true;
        var matched = true;
        for (final condition in conditions) {
          final result = _matches(condition);
          isValid = isValid && result.isValid;
          matched = matched && result.matches;
        }
        return isValid
            ? _ConditionMatch(matches: matched)
            : const _ConditionMatch.invalid();
      case AnyCondition(:final conditions):
        var isValid = true;
        var matched = false;
        for (final condition in conditions) {
          final result = _matches(condition);
          isValid = isValid && result.isValid;
          matched = matched || result.matches;
        }
        return isValid
            ? _ConditionMatch(matches: matched)
            : const _ConditionMatch.invalid();
      case NotCondition(:final condition):
        final result = _matches(condition);
        return result.isValid
            ? _ConditionMatch(matches: !result.matches)
            : result;
      case Condition():
        report(
          Diagnostic(
            code: DiagnosticCodes.resolutionUnsupportedCondition,
            target: DiagnosticTarget(kind: 'condition'),
            message:
                'Style `${styleId.value}` uses an unsupported condition type '
                '`${condition.runtimeType}`.',
          ),
        );
        return const _ConditionMatch.invalid();
    }
  }

  ResolvedAppearance resolveAppearance(Appearance appearance) {
    return ResolvedAppearance(
      surface: resolveSurface(appearance.surface),
      content: resolveContent(appearance.content),
      metrics: resolveMetrics(appearance.metrics),
    );
  }

  ResolvedSurface? resolveSurface(Surface? surface) {
    if (surface == null) {
      return null;
    }

    return ResolvedSurface(
      fill: resolveProperty(surface.fill),
      stroke: resolveProperty(surface.stroke),
      radius: resolveProperty(surface.radius),
      elevation: resolveProperty(surface.elevation),
    );
  }

  ResolvedContent? resolveContent(Content? content) {
    if (content == null) {
      return null;
    }

    return ResolvedContent(
      color: resolveProperty(content.color),
      text: resolveProperty(content.text),
      icon: resolveProperty(content.icon),
      opacity: resolveProperty(content.opacity),
    );
  }

  ResolvedMetrics? resolveMetrics(Metrics? metrics) {
    if (metrics == null) {
      return null;
    }

    return ResolvedMetrics(
      padding: resolveInsets(metrics.padding),
      gap: resolveProperty(metrics.gap),
      width: resolveProperty(metrics.width),
      height: resolveProperty(metrics.height),
      minWidth: resolveProperty(metrics.minWidth),
      minHeight: resolveProperty(metrics.minHeight),
      maxWidth: resolveProperty(metrics.maxWidth),
      maxHeight: resolveProperty(metrics.maxHeight),
    );
  }

  ResolvedInsets? resolveInsets(Insets? insets) {
    if (insets == null) {
      return null;
    }

    return ResolvedInsets(
      top: resolveProperty(insets.top),
      right: resolveProperty(insets.right),
      bottom: resolveProperty(insets.bottom),
      left: resolveProperty(insets.left),
    );
  }

  T? resolveProperty<T>(Property<T>? property) {
    switch (property) {
      case null:
        return null;
      case LiteralProperty<T>(:final value):
        return value;
      case TermProperty<T>(:final term):
        final termId = term.id.value;
        final assignment = _assignments[termId];
        if (assignment == null) {
          report(
            Diagnostic(
              code: DiagnosticCodes.resolutionUnresolvedTerm,
              target: DiagnosticTarget(kind: 'term', name: termId),
              message:
                  'Style `${styleId.value}` references term `$termId`, but '
                  'binding does not assign it.',
            ),
          );
          return null;
        }

        if (!term.acceptsValue(assignment.value)) {
          report(
            Diagnostic(
              code: DiagnosticCodes.resolutionInvalidTermValueType,
              target: DiagnosticTarget(kind: 'term', name: termId),
              message:
                  'Style `${styleId.value}` resolves term `$termId` from a '
                  '${assignment.value.runtimeType} value, but the property '
                  'expects ${term.valueType}.',
            ),
          );
          return null;
        }

        return assignment.value as T;
    }
  }
}

final class _ConditionMatch {
  const _ConditionMatch({required this.matches}) : isValid = true;

  const _ConditionMatch.invalid() : matches = false, isValid = false;

  final bool matches;
  final bool isValid;
}

Map<String, Assignment<Object?>> _assignmentsById(
  Iterable<Assignment<Object?>> assignments,
) {
  final assignmentsById = <String, Assignment<Object?>>{};

  for (final assignment in assignments) {
    assignmentsById.putIfAbsent(assignment.term.id.value, () => assignment);
  }

  return assignmentsById;
}
