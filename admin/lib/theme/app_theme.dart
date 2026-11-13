import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Colours the design system gives per theme that are not Material roles.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.dark,
    required this.buttonPrimaryBg,
    required this.buttonPrimaryText,
    required this.buttonOutlineBorder,
    required this.chipSelectedBg,
    required this.chipSelectedText,
    required this.surfaceVariant,
  });

  final bool dark;
  final Color buttonPrimaryBg;
  final Color buttonPrimaryText;
  final Color buttonOutlineBorder;
  final Color chipSelectedBg;
  final Color chipSelectedText;

  /// The M3 surfaceVariant role from the design file (disabled buttons).
  final Color surfaceVariant;

  static const light = AppColors(
    dark: false,
    buttonPrimaryBg: Palette.green,
    buttonPrimaryText: Palette.white,
    buttonOutlineBorder: Palette.green,
    chipSelectedBg: Palette.green,
    chipSelectedText: Palette.white,
    surfaceVariant: Palette.bg3,
  );

  static const darkColors = AppColors(
    dark: true,
    buttonPrimaryBg: Palette.greenBright,
    buttonPrimaryText: Accent.onGreenDark,
    buttonOutlineBorder: Color(0xFF365246),
    chipSelectedBg: Palette.greenBright,
    chipSelectedText: Accent.onGreenDark,
    surfaceVariant: Accent.darkCard2,
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 || other is! AppColors ? this : other;
}

/// 2.4 Material 3 colour roles.
const lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Palette.green,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Palette.greenExtraLight,
  onPrimaryContainer: Color(0xFF002117),
  secondary: Palette.red,
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFFE4E7),
  onSecondaryContainer: Color(0xFF410008),
  tertiary: Palette.success,
  onTertiary: Color(0xFFFFFFFF),
  error: Palette.error,
  onError: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF0B1511),
  onSurfaceVariant: Palette.text2,
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Palette.bg2,
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceContainerHigh: Palette.chip,
  surfaceContainerHighest: Palette.bg3,
  inverseSurface: Palette.ink,
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Palette.greenBright,
  outline: Color(0xFFC3D0CA),
  outlineVariant: Palette.stroke,
  surfaceTint: Color(0x00000000),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Palette.greenBright,
  onPrimary: Accent.onGreenDark,
  primaryContainer: Color(0xFF0B3D2C),
  onPrimaryContainer: Palette.greenExtraLight,
  secondary: Palette.redLight,
  onSecondary: Color(0xFF3B0008),
  secondaryContainer: Color(0xFF5C0F19),
  onSecondaryContainer: Color(0xFFFFDADF),
  tertiary: Color(0xFF3FD6A4),
  onTertiary: Accent.onGreenDark,
  error: Color(0xFFFF7A7A),
  onError: Color(0xFF2B0000),
  surface: Accent.darkBg,
  onSurface: Color(0xFFF1F6F3),
  onSurfaceVariant: Color(0xFFA5B7AE),
  surfaceContainerLowest: Color(0xFF040C09),
  surfaceContainerLow: Color(0xFF0C1913),
  surfaceContainer: Accent.darkCard,
  surfaceContainerHigh: Accent.darkCard2,
  surfaceContainerHighest: Color(0xFF21362C),
  inverseSurface: Color(0xFFFFFFFF),
  onInverseSurface: Palette.ink,
  inversePrimary: Palette.green,
  outline: Color(0xFF365246),
  outlineVariant: Color(0xFF1F3329),
  surfaceTint: Color(0x00000000),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// DM Sans at a weight, set through the variable font's weight axis.
TextStyle dm(double size, double height, int weight, {double? spacing}) =>
    TextStyle(
      fontFamily: Fonts.body,
      fontFamilyFallback: Fonts.fallback,
      fontSize: size,
      height: height / size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation.weight(weight.toDouble())],
      letterSpacing: spacing,
    );

/// Anton for display titles. Bangla falls back to Noto Sans Bengali, made
/// bold and narrow through its weight and width axes so it sits close to
/// Anton's heavy condensed look (Anton itself has no axes and ignores them).
TextStyle anton(double size, double height, double spacing) => TextStyle(
  fontFamily: Fonts.display,
  fontFamilyFallback: Fonts.fallback,
  fontSize: size,
  height: height / size,
  fontWeight: FontWeight.w400,
  fontVariations: const [FontVariation.weight(750), FontVariation.width(80)],
  letterSpacing: spacing,
);

/// 3. Type scale.
final appTextTheme = TextTheme(
  displaySmall: anton(34, 40, 0.3),
  headlineLarge: anton(21, 27, 0.4), // page titles, ALWAYS uppercase
  headlineSmall: dm(22, 28, 700),
  titleLarge: dm(20, 26, 600),
  titleMedium: dm(16, 22, 600),
  titleSmall: dm(14, 20, 600),
  // Body lines are a little taller than FLARECAP's 23/20/16 because Bangla
  // letters carry marks above and below the line.
  bodyLarge: dm(16, 25, 400),
  bodyMedium: dm(14, 21, 400),
  bodySmall: dm(12, 17, 400),
  labelLarge: dm(14, 18, 500),
  labelMedium: dm(12, 16, 500),
  labelSmall: dm(11, 14, 500),
);

/// Extra named styles from the type scale.
abstract final class AppText {
  static final sectionTitle = dm(12, 18, 500, spacing: 1.2);
  static final buttonPrimary = dm(16, 22, 500);
  static final buttonOutline = dm(14, 20, 500);
  static final pill = dm(11, 14, 600);
  static final navLabel = dm(12, 16, 400);
  static const code = TextStyle(
    fontFamily: Fonts.mono,
    fontFamilyFallback: Fonts.fallback,
    fontSize: 13,
    height: 20 / 13,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final s = dark ? darkScheme : lightScheme;
  final app = dark ? AppColors.darkColors : AppColors.light;
  final text = appTextTheme.apply(
    bodyColor: s.onSurface,
    displayColor: s.onSurface,
  );
  RoundedRectangleBorder r(double v) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(v));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: s,
    textTheme: text,
    fontFamily: Fonts.body,
    fontFamilyFallback: Fonts.fallback,
    scaffoldBackgroundColor: s.surface,
    canvasColor: s.surface,
    dividerColor: s.outlineVariant,
    splashFactory: InkRipple.splashFactory,
    extensions: [app],
    iconTheme: IconThemeData(color: s.onSurface, size: Sizes.icon),
    dividerTheme: DividerThemeData(
      color: s.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: app.buttonPrimaryBg,
        foregroundColor: app.buttonPrimaryText,
        disabledBackgroundColor: app.surfaceVariant,
        disabledForegroundColor: s.onSurfaceVariant,
        minimumSize: const Size(0, Sizes.buttonPrimaryMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: r(Radii.button),
        textStyle: AppText.buttonPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.onSurface,
        minimumSize: const Size(0, Sizes.buttonOutlineMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: r(Radii.button),
        side: BorderSide(color: app.buttonOutlineBorder),
        textStyle: AppText.buttonOutline,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: s.primary,
        textStyle: text.labelLarge,
        shape: r(Radii.button),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: s.onSurface,
        minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
        iconSize: Sizes.icon,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: BorderSide(color: s.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: BorderSide(color: s.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
        borderSide: BorderSide(color: s.primary, width: 2),
      ),
      hintStyle: text.bodyLarge?.copyWith(color: s.onSurfaceVariant),
      helperStyle: text.bodySmall?.copyWith(color: s.onSurfaceVariant),
      helperMaxLines: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.primary,
      selectionColor: s.primary.withValues(alpha: Alphas.circleActionBorder),
      selectionHandleColor: s.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? Palette.white : s.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? s.primary
            : s.surfaceContainerHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: s.primary,
      thumbColor: s.primary,
      inactiveTrackColor: s.surfaceContainerHighest,
      valueIndicatorTextStyle: text.labelLarge?.copyWith(color: s.onPrimary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.primary,
      linearTrackColor: s.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: r(Radii.hero),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(color: s.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainer,
      modalBackgroundColor: s.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: s.outline,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.hero)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: s.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      width: Layout.sidebarWidth,
      shape: const RoundedRectangleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface),
      actionTextColor: dark ? Palette.green : Palette.greenBright,
      behavior: SnackBarBehavior.floating,
      shape: r(Radii.button),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: s.inverseSurface,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      textStyle: text.bodySmall?.copyWith(color: s.onInverseSurface),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.tile),
        side: BorderSide(color: s.outlineVariant),
      ),
      textStyle: text.bodyLarge,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeScalePageTransitionsBuilder(),
        TargetPlatform.iOS: FadeScalePageTransitionsBuilder(),
      },
    ),
  );
}

/// 8. Opening a full screen: fade in + scale in from 0.96 (no slides, no bounce).
class FadeScalePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeScalePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(
          begin: Motion.screenEnterScaleFrom,
          end: 1.0,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
