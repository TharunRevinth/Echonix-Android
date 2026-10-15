import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/dominant_color_provider.dart';
import 'package:client/core/theme/glass.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/view/widgets/music_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MusicSlab extends ConsumerWidget {
  final VoidCallback? onOpenPlayer;

  const MusicSlab({super.key, this.onOpenPlayer});

  void _defaultOpenPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const MusicPlayer();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero).chain(
            CurveTween(curve: Curves.easeOutCubic),
          );
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSong = ref.watch(currentSongNotifierProvider.select((s) => s != null));
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);

    if (!hasSong) {
      return const SizedBox();
    }

    final songName = ref.watch(currentSongNotifierProvider.select((s) => s?.song_name ?? ''));
    final artist = ref.watch(currentSongNotifierProvider.select((s) => s?.artist ?? ''));
    final thumb = ref.watch(currentSongNotifierProvider.select((s) => s?.thumbnail_url ?? ''));
    final hexCode = ref.watch(currentSongNotifierProvider.select((s) => s?.hex_code ?? 'B388FF'));

    final dominantColorAsync = ref.watch(dominantColorProvider(thumb));
    final baseColor = dominantColorAsync.valueOrNull ?? hexToColor(hexCode);

    return GestureDetector(
      onTap: onOpenPlayer ?? () => _defaultOpenPlayer(context),
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0.0;
        if (v < -200) {
          songNotifier.next();
        } else if (v > 200) {
          songNotifier.previous();
        }
      },
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) < -5) {
          if (onOpenPlayer != null) {
            onOpenPlayer!();
          } else {
            _defaultOpenPlayer(context);
          }
        }
      },
      child: GlassSurface(
        borderRadius: 16,
        blurSigma: 18,
        tintColor: baseColor,
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: Row(
                  children: [
                    Hero(
                      tag: 'music-image',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: thumb,
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
                            songName,
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
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.7),
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
                        const SizedBox(width: 14),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: songNotifier.next,
                          icon: const Icon(
                            CupertinoIcons.forward_fill,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ],
                ),
              ),
              // Background track progress line
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2.0,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              // Active progress line
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
                        height: 2.0,
                        color: Colors.white,
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
