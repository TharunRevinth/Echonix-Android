import 'package:client/core/theme/glass.dart';
import 'package:client/features/home/view/pages/library_page.dart';
import 'package:client/features/home/view/pages/search_page.dart';
import 'package:client/features/home/view/pages/settings_page.dart';
import 'package:client/features/home/view/pages/songs_page.dart';
import 'package:client/features/home/view/widgets/music_player.dart';
import 'package:client/features/home/view/widgets/music_slab.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/widgets/stream_diagnostics_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);
final searchQueryProvider = StateProvider<String>((ref) => '');

final dockHeightProvider = Provider<double>((ref) {
  final hasSong = ref.watch(currentSongNotifierProvider.select((s) => s != null));
  return hasSong ? 128.0 : 64.0;
});

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
    ref.listen<String?>(playbackErrorProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            action: SnackBarAction(
              label: 'Details',
              onPressed: () {
                final currentSong = ref.read(currentSongNotifierProvider);
                showStreamDiagnosticsDialog(context, ref, currentSong?.id);
              },
            ),
          ),
        );
      }
    });

    final selectedIndex = ref.watch(homeTabIndexProvider);
    final hasSong = ref.watch(currentSongNotifierProvider.select((s) => s != null));
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: PopScope(
        canPop: _playerController.value < 0.05,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_playerController.value >= 0.05) {
            _closePlayer();
          } else if (selectedIndex != 0) {
            ref.read(homeTabIndexProvider.notifier).state = 0;
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Tab content pages with IndexedStack (prevents tab thrashing and dropped frames)
            Positioned.fill(
              child: IndexedStack(
                index: selectedIndex,
                children: pages,
              ),
            ),

            // 2. Liquid Glass Dock: one GlassDock anchored 12 dp above the bottom safe area, 12 dp side margins, radius 28
            Positioned(
              bottom: 12 + bottomInset,
              left: 12,
              right: 12,
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
                child: GlassDock(
                  borderRadius: 28,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSong)
                        MusicSlab(
                          onOpenPlayer: _openPlayer,
                        ),
                      SizedBox(
                        height: 64,
                        child: NavigationBar(
                          selectedIndex: selectedIndex,
                          onDestinationSelected: (index) {
                            HapticFeedback.lightImpact();
                            ref.read(homeTabIndexProvider.notifier).state = index;
                          },
                          backgroundColor: Colors.transparent,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.home_outlined),
                              selectedIcon: Icon(Icons.home_rounded),
                              label: 'Home',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.search_outlined),
                              selectedIcon: Icon(Icons.search_rounded),
                              label: 'Search',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.library_music_outlined),
                              selectedIcon: Icon(Icons.library_music_rounded),
                              label: 'Library',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.settings_outlined),
                              selectedIcon: Icon(Icons.settings_rounded),
                              label: 'Settings',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Draggable Full Player Sheet (Spring simulation, cached child widget)
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
                    child: child,
                  );
                },
                child: MusicPlayer(
                  onClose: _closePlayer,
                  onVerticalDragUpdate: (delta) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    _playerController.value =
                        (_playerController.value - delta / screenHeight).clamp(0.0, 1.0);
                  },
                  onVerticalDragEnd: (velocity) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final v = -velocity / screenHeight;
                    if (v < -0.4 || _playerController.value < 0.6) {
                      _closePlayer(velocity: v);
                    } else {
                      _openPlayer(velocity: v);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
