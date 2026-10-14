import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/dominant_color_provider.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/view/widgets/music_player.dart';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MusicSlab extends ConsumerWidget {
  const MusicSlab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongNotifierProvider);
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);
    final isLiked = ref.watch(likedSongIdsProvider.select((ids) => ids.contains(currentSong?.id)));

    if (currentSong == null) {
      return const SizedBox();
    }

    final dominantColorAsync = ref.watch(dominantColorProvider(currentSong.thumbnail_url));
    final baseColor = dominantColorAsync.valueOrNull ?? hexToColor(currentSong.hex_code);

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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: currentSong.thumbnail_url,
                        width: 48,
                        height: 48,
                        memCacheWidth: 96,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          width: 48,
                          height: 48,
                          color: const Color(0xFF212121),
                          child: const Icon(Icons.music_note, color: Colors.white54),
                        ),
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
                        onPressed: () {
                          ref.read(likedSongIdsProvider.notifier).toggle(currentSong);
                        },
                        icon: Icon(
                          isLiked
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          color: isLiked
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
