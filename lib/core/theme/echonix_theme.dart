import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dominant_color_provider.dart';

const Color kBrandSeed = Color(0xFF8E6BFF);

class EchoGlass extends ThemeExtension<EchoGlass> {
  final Color fill;
  final Color fillOff;
  final Color strokeStart;
  final Color strokeEnd;
  final Color highlight;
  final double dockBlur;

  const EchoGlass({
    required this.fill,
    required this.fillOff,
    required this.strokeStart,
    required this.strokeEnd,
    required this.highlight,
    required this.dockBlur,
  });

  factory EchoGlass.fromScheme(ColorScheme scheme) {
    return EchoGlass(
      fill: scheme.surfaceContainerHigh.withValues(alpha: 0.62),
      fillOff: scheme.surfaceContainerHigh,
      strokeStart: scheme.onSurface.withValues(alpha: 0.28),
      strokeEnd: scheme.onSurface.withValues(alpha: 0.04),
      highlight: scheme.onSurface.withValues(alpha: 0.22),
      dockBlur: 14.0,
    );
  }

  @override
  EchoGlass copyWith({
    Color? fill,
    Color? fillOff,
    Color? strokeStart,
    Color? strokeEnd,
    Color? highlight,
    double? dockBlur,
  }) {
    return EchoGlass(
      fill: fill ?? this.fill,
      fillOff: fillOff ?? this.fillOff,
      strokeStart: strokeStart ?? this.strokeStart,
      strokeEnd: strokeEnd ?? this.strokeEnd,
      highlight: highlight ?? this.highlight,
      dockBlur: dockBlur ?? this.dockBlur,
    );
  }

  @override
  EchoGlass lerp(ThemeExtension<EchoGlass>? other, double t) {
    if (other is! EchoGlass) return this;
    return EchoGlass(
      fill: Color.lerp(fill, other.fill, t) ?? fill,
      fillOff: Color.lerp(fillOff, other.fillOff, t) ?? fillOff,
      strokeStart: Color.lerp(strokeStart, other.strokeStart, t) ?? strokeStart,
      strokeEnd: Color.lerp(strokeEnd, other.strokeEnd, t) ?? strokeEnd,
      highlight: Color.lerp(highlight, other.highlight, t) ?? highlight,
      dockBlur: dockBlur + (other.dockBlur - dockBlur) * t,
    );
  }
}

class EchonixTheme {
  static final ColorScheme _base = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );

  static final ColorScheme darkColorScheme = _base.copyWith(
    surface: const Color(0xFF0A0910),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0F0D16),
    surfaceContainer: const Color(0xFF14111D),
    surfaceContainerHigh: const Color(0xFF1B1726),
    surfaceContainerHighest: const Color(0xFF231E2F),
  );

  static final EchoGlass echoGlassDark = EchoGlass.fromScheme(darkColorScheme);

  static ThemeData get darkTheme {
    final scheme = darkColorScheme;
    final baseTextTheme = Typography.material2021(platform: TargetPlatform.android).white;
    final textTheme = baseTextTheme.copyWith(
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        elevation: 8,
        modalElevation: 8,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.onSecondaryContainer, size: 24);
          }
          return IconThemeData(color: scheme.onSurfaceVariant, size: 24);
        }),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4.0,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant, width: 1.0),
        labelStyle: textTheme.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: ShapeDecoration(
          shape: const StadiumBorder(),
          color: scheme.secondaryContainer,
        ),
        labelColor: scheme.onSecondaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1.0,
        space: 1.0,
      ),
      extensions: [
        echoGlassDark,
      ],
    );
  }
}

final matchArtworkColorsProvider = StateProvider<bool>((ref) => true);

final playerSchemeProvider = Provider.family<ColorScheme, String>((ref, thumbUrl) {
  final match = ref.watch(matchArtworkColorsProvider);
  if (!match) {
    return EchonixTheme.darkColorScheme;
  }
  final dominantAsync = ref.watch(dominantColorProvider(thumbUrl));
  final dominant = dominantAsync.valueOrNull ?? EchonixTheme.darkColorScheme.primary;
  final base = ColorScheme.fromSeed(
    seedColor: dominant,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );
  return base.copyWith(
    surface: const Color(0xFF0A0910),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF0F0D16),
    surfaceContainer: const Color(0xFF14111D),
    surfaceContainerHigh: const Color(0xFF1B1726),
    surfaceContainerHighest: const Color(0xFF231E2F),
  );
});

