import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Design roles that Material 3 has no slot for.
///
/// Three families live here rather than being squeezed into unrelated M3
/// slots, because forcing them in would silently break the contrast guarantee:
///
/// * `status*` — On track / Needs attention / Action required. `needsAttention`
///   is an amber ramp deliberately unreachable from the red one, so a status
///   chip can never drift into looking like an error.
/// * `connectivity*` — offline is a neutral slate, never red. Offline is a
///   normal operating state for this product, not a failure.
/// * `ink*` — the dark counterpoint surface. In dark mode it inverts and
///   *lifts*, because a "darker card" is impossible on a pitch-black page.
/// * `glass*` / `scrim*` — alphas tuned so every foreground stays >= 4.5:1
///   composited over both black and white, since a blurred surface has no
///   fixed background.
@immutable
class AlmanacSemantics extends ThemeExtension<AlmanacSemantics> {
  final AlmanacColors colors;

  const AlmanacSemantics(this.colors);

  @override
  AlmanacSemantics copyWith({AlmanacColors? colors}) =>
      AlmanacSemantics(colors ?? this.colors);

  /// Colour roles are a discrete design decision, not a continuum — a
  /// half-interpolated status amber is not a colour anyone chose. Snapping at
  /// the midpoint keeps every rendered frame on a verified value.
  @override
  AlmanacSemantics lerp(covariant AlmanacSemantics? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Reads the semantic roles for the active theme.
extension AlmanacTheme on BuildContext {
  AlmanacColors get semantic =>
      Theme.of(this).extension<AlmanacSemantics>()!.colors;
}

/// Inter is bundled (SIL OFL, redistributable) so the design survives on the
/// target device. San Francisco cannot legally ship in an Android APK, and the
/// farmer's Galaxy A13 would render Roboto — a visibly different face.
const _fontFamily = 'Inter';

ThemeData almanacLightTheme() => _theme(Brightness.light, almanacColorsLight);
ThemeData almanacDarkTheme() => _theme(Brightness.dark, almanacColorsDark);

ThemeData _theme(Brightness brightness, AlmanacColors c) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.secondaryContainer,
    onSecondaryContainer: c.onSecondaryContainer,
    tertiary: c.tertiary,
    onTertiary: c.onTertiary,
    tertiaryContainer: c.tertiaryContainer,
    onTertiaryContainer: c.onTertiaryContainer,
    // Material's `error` maps to the most severe status role, so stock widgets
    // (TextField validation, etc.) speak the same language as our own chips.
    error: c.statusActionRequired,
    onError: brightness == Brightness.light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF4C0B06),
    errorContainer: c.statusActionRequiredContainer,
    onErrorContainer: c.onStatusActionRequiredContainer,
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceVariant,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceContainerHigh,
    surfaceContainerHighest: c.surfaceContainerHigh,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
    // The design's pitch-black page is darker than `surface`, which is what
    // `scaffoldBackgroundColor` below actually paints.
    inverseSurface: c.onSurface,
    onInverseSurface: c.surface,
    inversePrimary: c.primaryContainer,
    shadow: const Color(0xFF000000),
    scrim: c.backdrop,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    fontFamily: _fontFamily,
    textTheme: _textTheme(c.onSurface),
    splashFactory: InkSparkle.splashFactory,
    extensions: [AlmanacSemantics(c)],
  );
}

TextStyle _style(AlmanacTypeToken t, Color color) => TextStyle(
  fontFamily: _fontFamily,
  fontSize: t.size,
  height: t.heightFactor,
  fontWeight: FontWeight.values[(t.weight ~/ 100) - 1],
  color: color,
);

/// Maps the design's type scale onto Material 3's roles.
///
/// `displayLarge` is the design's one display token; M3's `displayMedium` and
/// `displaySmall` are deliberately absent from the design set, so they inherit
/// rather than being invented here. Nothing resolves below 13px.
TextTheme _textTheme(Color onSurface) => TextTheme(
  displayLarge: _style(AlmanacType.displayL, onSurface),
  headlineLarge: _style(AlmanacType.headlineL, onSurface),
  headlineMedium: _style(AlmanacType.headlineM, onSurface),
  headlineSmall: _style(AlmanacType.headlineS, onSurface),
  titleLarge: _style(AlmanacType.titleL, onSurface),
  titleMedium: _style(AlmanacType.titleM, onSurface),
  titleSmall: _style(AlmanacType.titleS, onSurface),
  bodyLarge: _style(AlmanacType.bodyL, onSurface),
  bodyMedium: _style(AlmanacType.bodyM, onSurface),
  bodySmall: _style(AlmanacType.bodyS, onSurface),
  labelLarge: _style(AlmanacType.labelL, onSurface),
  labelMedium: _style(AlmanacType.labelM, onSurface),
  labelSmall: _style(AlmanacType.labelS, onSurface),
);
