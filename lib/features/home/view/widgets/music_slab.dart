import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/current_user_notifier.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/view/widgets/music_player.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

class MusicSlab extends ConsumerStatefulWidget {
  const MusicSlab({super.key});

  @override
  ConsumerState<MusicSlab> createState() => _MusicSlabState();
}

class _MusicSlabState extends ConsumerState<MusicSlab> {
  Color? _extractedColor;
  String? _loadedImageUrl;

  void _extractColor(String imageUrl) async {
    if (_loadedImageUrl == imageUrl) return;
    _loadedImageUrl = imageUrl;
    try {
      final provider = NetworkImage(imageUrl);
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 3,
      );
      if (mounted && palette.dominantColor != null) {
        setState(() {
          _extractedColor = palette.dominantColor!.color;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongNotifierProvider);
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);
    final userFavorites = ref.watch(
      currentUserNotifierProvider.select((data) => data?.favorites ?? []),
    );

    if (currentSong == null) {
      return const SizedBox();
    }

    if (_loadedImageUrl != currentSong.thumbnail_url) {
      _extractedColor = null;
      _extractColor(currentSong.thumbnail_url);
    }
    final baseColor = _extractedColor ?? hexToColor(currentSong.hex_code);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) {
              return const MusicPlayer();
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final tween =
                  Tween(begin: const Offset(0, 1), end: Offset.zero).chain(
                CurveTween(
                  curve: Curves.easeOutCubic,
                ),
              );
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor.withOpacity(0.25),
              const Color(0xFF0C0C0C),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: Row(
                children: [
                  Hero(
                    tag: 'music-image',
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(currentSong.thumbnail_url),
                          fit: BoxFit.cover,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          currentSong.song_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentSong.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          await ref.read(homeViewModelProvider.notifier).favSong(
                                songId: currentSong.id,
                              );
                        },
                        icon: Icon(
                          userFavorites.any((fav) => fav.song_id == currentSong.id)
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          color: userFavorites.any((fav) => fav.song_id == currentSong.id)
                              ? Colors.redAccent
                              : Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: songNotifier.playPause,
                        icon: ref.watch(isPlayerLoadingProvider)
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                ref.watch(isPlayingProvider).value ?? false
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: Colors.white,
                                size: 26,
                              ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            ),
            // Progress line at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: StreamBuilder<Duration>(
                stream: songNotifier.audioPlayer?.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = songNotifier.audioPlayer?.duration ?? Duration.zero;
                  double progress = 0.0;
                  if (duration.inMilliseconds > 0) {
                    progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                  }
                  return FractionallySizedBox(
                    alignment: Alignment.bottomLeft,
                    widthFactor: progress,
                    child: Container(
                      height: 2.5,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
            // Track background progress line
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2.5,
                color: Colors.white10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
