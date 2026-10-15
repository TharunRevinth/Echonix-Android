import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/theme/echonix_theme.dart';
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
      return const SizedBox.shrink();
    }

    final songName = ref.watch(currentSongNotifierProvider.select((s) => s?.song_name ?? ''));
    final artist = ref.watch(currentSongNotifierProvider.select((s) => s?.artist ?? ''));
    final thumb = ref.watch(currentSongNotifierProvider.select((s) => s?.thumbnail_url ?? ''));

    final playerScheme = ref.watch(playerSchemeProvider(thumb));
    final textTheme = Theme.of(context).textTheme;

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: playerScheme),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;

          return TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              begin: scheme.surfaceContainerHigh,
              end: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
            ),
            duration: const Duration(milliseconds: 400),
            curve: Easing.emphasizedDecelerate,
            builder: (context, animatedColor, child) {
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
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: animatedColor ?? scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'music-image',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: thumb,
                                  width: 44,
                                  height: 44,
                                  memCacheWidth: 96,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Container(
                                    width: 44,
                                    height: 44,
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
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
                                    style: textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: scheme.primaryContainer,
                                    foregroundColor: scheme.onPrimaryContainer,
                                  ),
                                  onPressed: songNotifier.playPause,
                                  icon: ref.watch(isPlayerLoadingProvider)
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: scheme.onPrimaryContainer,
                                          ),
                                        )
                                      : Icon(
                                          ref.watch(isPlayingProvider).value ?? false
                                              ? CupertinoIcons.pause_fill
                                              : CupertinoIcons.play_fill,
                                          size: 22,
                                        ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: songNotifier.next,
                                  icon: Icon(
                                    CupertinoIcons.forward_fill,
                                    color: scheme.onSurface,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Dedicated StreamBuilder wrapping ONLY the 2 px progress indicator
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
                            return LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.0,
                              backgroundColor: scheme.surfaceContainerHighest,
                              color: scheme.primary,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
