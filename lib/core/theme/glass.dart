import 'dart:ui';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualEffectsMode {
  full,
  reduced,
}

class VisualEffectsNotifier extends StateNotifier<VisualEffectsMode> {
  VisualEffectsNotifier() : super(VisualEffectsMode.full) {
    _load();
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('visual_effects_mode');
    if (saved != null) {
      state = saved == 'reduced' ? VisualEffectsMode.reduced : VisualEffectsMode.full;
    }
  }

  void setMode(VisualEffectsMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('visual_effects_mode', mode.name);
  }

  void toggle() {
    setMode(state == VisualEffectsMode.full ? VisualEffectsMode.reduced : VisualEffectsMode.full);
  }
}

final visualEffectsModeProvider =
    StateNotifierProvider<VisualEffectsNotifier, VisualEffectsMode>((ref) {
  return VisualEffectsNotifier();
});

class GlassPhysics {
  static const double stiffness = 180.0;
  static const double damping = 22.0;

  static SpringDescription get spring => const SpringDescription(
        mass: 1.0,
        stiffness: stiffness,
        damping: damping,
      );

  static SpringSimulation createSimulation({
    required double start,
    required double end,
    required double velocity,
  }) {
    return SpringSimulation(spring, start, end, velocity);
  }
}

class GlassSurface extends ConsumerWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? tintColor;
  final bool showShadow;
  final VoidCallback? onTap;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.blurSigma = 18.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tintColor,
    this.showShadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectsMode = ref.watch(visualEffectsModeProvider);
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isReduced = effectsMode == VisualEffectsMode.reduced || disableAnimations;

    final dominantColor = tintColor ?? const Color(0xFF7C4DFF);

    final content = CustomPaint(
      foregroundPainter: _InnerHighlightPainter(
        radius: borderRadius,
        highlightColor: Colors.white.withOpacity(0.25),
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              dominantColor.withOpacity(0.18),
              Colors.white.withOpacity(0.08),
            ],
          ),
          border: Border.all(
            width: 1.0,
            color: Colors.transparent, // Replaced below by gradient border
          ),
        ),
        child: child,
      ),
    );

    // Border painter for top-left to bottom-right white gradient
    final borderedContent = CustomPaint(
      painter: _GradientBorderPainter(
        radius: borderRadius,
        strokeWidth: 1.0,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.35),
            Colors.white.withOpacity(0.05),
          ],
        ),
      ),
      child: content,
    );

    Widget result;
    if (isReduced) {
      result = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: const Color(0xFF16121E).withOpacity(0.85),
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: borderedContent,
        ),
      );
    } else {
      result = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: borderedContent,
            ),
          ),
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: result,
      );
    }
    return result;
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Gradient gradient;

  _GradientBorderPainter({
    required this.radius,
    required this.strokeWidth,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.strokeWidth != strokeWidth;
}

class _InnerHighlightPainter extends CustomPainter {
  final double radius;
  final Color highlightColor;

  _InnerHighlightPainter({
    required this.radius,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final path = Path();
    final r = radius.clamp(0.0, size.height / 2);
    path.moveTo(r, 0.5);
    path.lineTo(size.width - r, 0.5);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = highlightColor;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_InnerHighlightPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.highlightColor != highlightColor;
}
