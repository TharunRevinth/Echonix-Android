import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualEffectsMode {
  off,
  balanced,
  full,
}

class VisualEffectsNotifier extends StateNotifier<VisualEffectsMode> {
  VisualEffectsNotifier() : super(VisualEffectsMode.balanced) {
    _load();
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('visual_effects_mode');
    if (saved != null) {
      if (saved == 'off') {
        state = VisualEffectsMode.off;
      } else if (saved == 'full') {
        state = VisualEffectsMode.full;
      } else {
        state = VisualEffectsMode.balanced;
      }
    }
  }

  void setMode(VisualEffectsMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('visual_effects_mode', mode.name);
  }

  void toggle() {
    switch (state) {
      case VisualEffectsMode.off:
        setMode(VisualEffectsMode.balanced);
        break;
      case VisualEffectsMode.balanced:
        setMode(VisualEffectsMode.full);
        break;
      case VisualEffectsMode.full:
        setMode(VisualEffectsMode.off);
        break;
    }
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

/// GlassDock combines dock elements (such as bottom bar & mini-player) into a
/// SINGLE offscreen BackdropFilter pass to eliminate Mali GPU fragment shader bottlenecks.
class GlassDock extends ConsumerWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;

  const GlassDock({
    super.key,
    required this.child,
    this.borderRadius = 26.0,
    this.margin,
    this.padding,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(visualEffectsModeProvider);
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isOff = mode == VisualEffectsMode.off || disableAnimations;
    final double sigma = isOff ? 0.0 : (mode == VisualEffectsMode.full ? 22.0 : 14.0);

    final bgTint = (tintColor ?? const Color(0xFF140D20)).withValues(alpha: isOff ? 0.95 : 0.72);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgTint,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: child,
    );

    if (sigma > 0) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    return RepaintBoundary(
      child: Container(
        margin: margin,
        child: content,
      ),
    );
  }
}

/// GlassSurface is an efficient static painted surface without BackdropFilter or multi-pass shadows,
/// eliminating the 12+ offscreen render passes that choke mobile Mali GPUs.
class GlassSurface extends StatelessWidget {
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
    this.borderRadius = 16.0,
    this.blurSigma = 0.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tintColor,
    this.showShadow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dominantColor = tintColor ?? const Color(0xFF1A1326);

    Widget result = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: dominantColor.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      result = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: result,
      );
    }

    return result;
  }
}
