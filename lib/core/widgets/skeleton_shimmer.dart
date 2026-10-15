import 'package:flutter/material.dart';

class ShimmerScope extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const ShimmerScope({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  });

  static Animation<double>? of(BuildContext context) {
    final _ShimmerInherited? scope =
        context.dependOnInheritedWidgetOfExactType<_ShimmerInherited>();
    return scope?.animation;
  }

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerInherited(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _ShimmerInherited extends InheritedWidget {
  final Animation<double> animation;

  const _ShimmerInherited({
    required this.animation,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ShimmerInherited oldWidget) =>
      oldWidget.animation != animation;
}

class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SkeletonShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _fallbackController;

  @override
  void dispose() {
    _fallbackController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sharedAnim = ShimmerScope.of(context);
    final anim = sharedAnim ??
        (_fallbackController ??= AnimationController(
          vsync: this,
          duration: widget.duration,
        )..repeat());

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final t = anim.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                onSurface.withValues(alpha: 0.04),
                onSurface.withValues(alpha: 0.18),
                onSurface.withValues(alpha: 0.04),
              ],
              stops: [
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: SkeletonShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Quick picks title
              const SkeletonBox(width: 180, height: 28, borderRadius: 6),
              const SizedBox(height: 16),
              // Quick picks 2-column grid
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.8,
                ),
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Row(
                      children: [
                        SkeletonBox(width: 48, height: 48, borderRadius: 8),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 80, height: 12, borderRadius: 4),
                              SizedBox(height: 6),
                              SkeletonBox(width: 50, height: 10, borderRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              // Carousel title
              const SkeletonBox(width: 200, height: 28, borderRadius: 6),
              const SizedBox(height: 16),
              // Horizontal carousel of 150 px square cards
              SizedBox(
                height: 210,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  itemBuilder: (context, index) {
                    return const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 150, height: 150, borderRadius: 14),
                          SizedBox(height: 8),
                          SkeletonBox(width: 120, height: 12, borderRadius: 4),
                          SizedBox(height: 4),
                          SkeletonBox(width: 70, height: 10, borderRadius: 4),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchTrendingSkeleton extends StatelessWidget {
  const SearchTrendingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const SkeletonBox(width: 150, height: 22, borderRadius: 6),
            const SizedBox(height: 16),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.6,
              ),
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 44, height: 44, borderRadius: 8),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 70, height: 12, borderRadius: 4),
                            SizedBox(height: 6),
                            SkeletonBox(width: 45, height: 10, borderRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
