import 'package:client/core/theme/glass.dart';
import 'package:client/features/home/view/pages/library_page.dart';
import 'package:client/features/home/view/pages/search_page.dart';
import 'package:client/features/home/view/pages/settings_page.dart';
import 'package:client/features/home/view/pages/songs_page.dart';
import 'package:client/features/home/view/widgets/music_player.dart';
import 'package:client/features/home/view/widgets/music_slab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);
final searchQueryProvider = StateProvider<String>((ref) => '');

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _playerController;

  final pages = const [
    SongsPage(),
    SearchPage(),
    LibraryPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _playerController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  void _openPlayer({double velocity = 0.0}) {
    final sim = GlassPhysics.createSimulation(
      start: _playerController.value,
      end: 1.0,
      velocity: velocity,
    );
    _playerController.animateWith(sim);
  }

  void _closePlayer({double velocity = 0.0}) {
    final sim = GlassPhysics.createSimulation(
      start: _playerController.value,
      end: 0.0,
      velocity: velocity,
    );
    _playerController.animateWith(sim);
  }

  @override
  Widget build(BuildContext context) {
    print('[Echonix] 9. HomePage build() entered');
    final selectedIndex = ref.watch(homeTabIndexProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Tab content pages with animated fade-through & 12px vertical slide (P5-T3 transition)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.0, 12.0 / 800.0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(selectedIndex),
                child: pages[selectedIndex],
              ),
            ),
          ),

          // 2. Floating Mini-Player (Positioned above floating tab bar)
          Positioned(
            bottom: 12 + bottomInset + 58 + 10,
            left: 16,
            right: 16,
            child: AnimatedBuilder(
              animation: _playerController,
              builder: (context, child) {
                final val = _playerController.value.clamp(0.0, 1.0);
                final opacity = (1.0 - val * 2.5).clamp(0.0, 1.0);
                if (opacity <= 0.0) return const SizedBox.shrink();

                return Opacity(
                  opacity: opacity,
                  child: child,
                );
              },
              child: MusicSlab(
                onOpenPlayer: _openPlayer,
              ),
            ),
          ),

          // 3. Floating Glass Tab Bar with sliding spring pill indicator
          Positioned(
            bottom: 12 + bottomInset,
            left: 16,
            right: 16,
            child: AnimatedBuilder(
              animation: _playerController,
              builder: (context, child) {
                final val = _playerController.value.clamp(0.0, 1.0);
                final opacity = (1.0 - val * 2.5).clamp(0.0, 1.0);
                final translateY = val * 80.0;
                if (opacity <= 0.0) return const SizedBox.shrink();

                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, translateY),
                    child: child,
                  ),
                );
              },
              child: GlassSurface(
                borderRadius: 26,
                blurSigma: 18,
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Stack(
                  children: [
                    // Sliding filled pill indicator
                    _SpringSlidingIndicator(
                      selectedIndex: selectedIndex,
                      tabCount: 4,
                    ),
                    // Tab items
                    Row(
                      children: [
                        _buildTabItem(0, Icons.home_rounded, 'Home', selectedIndex),
                        _buildTabItem(1, Icons.search_rounded, 'Search', selectedIndex),
                        _buildTabItem(2, Icons.library_music_rounded, 'Library', selectedIndex),
                        _buildTabItem(3, Icons.settings_rounded, 'Settings', selectedIndex),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Draggable Full Player Sheet (Spring simulation)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _playerController,
              builder: (context, child) {
                final val = _playerController.value;
                if (val <= 0.001) return const SizedBox.shrink();

                final screenHeight = MediaQuery.of(context).size.height;
                final offset = (1.0 - val.clamp(0.0, 1.0)) * screenHeight;

                return Transform.translate(
                  offset: Offset(0, offset),
                  child: MusicPlayer(
                    onClose: _closePlayer,
                    dragProgress: val,
                    onVerticalDragUpdate: (delta) {
                      _playerController.value =
                          (_playerController.value - delta / screenHeight).clamp(0.0, 1.0);
                    },
                    onVerticalDragEnd: (velocity) {
                      final v = -velocity / screenHeight;
                      if (v < -0.4 || _playerController.value < 0.6) {
                        _closePlayer(velocity: v);
                      } else {
                        _openPlayer(velocity: v);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label, int selectedIndex) {
    final isSelected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(homeTabIndexProvider.notifier).state = index;
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.45),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.45),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpringSlidingIndicator extends StatefulWidget {
  final int selectedIndex;
  final int tabCount;

  const _SpringSlidingIndicator({
    required this.selectedIndex,
    required this.tabCount,
  });

  @override
  State<_SpringSlidingIndicator> createState() => _SpringSlidingIndicatorState();
}

class _SpringSlidingIndicatorState extends State<_SpringSlidingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _currentPosition = 0.0;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.selectedIndex.toDouble();
    _controller = AnimationController.unbounded(vsync: this, value: _currentPosition)
      ..addListener(() {
        setState(() {
          _currentPosition = _controller.value;
        });
      });
  }

  @override
  void didUpdateWidget(covariant _SpringSlidingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final sim = GlassPhysics.createSimulation(
        start: _currentPosition,
        end: widget.selectedIndex.toDouble(),
        velocity: 0.0,
      );
      _controller.animateWith(sim);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / widget.tabCount;
        final left = _currentPosition * tabWidth;

        return Stack(
          children: [
            Positioned(
              left: left + 2,
              top: 2,
              bottom: 2,
              width: tabWidth - 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.18),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
