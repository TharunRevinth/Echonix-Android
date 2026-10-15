import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/theme/echonix_theme.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(queueVersionProvider);
    final currentSong = ref.watch(currentSongNotifierProvider);
    final notifier = ref.read(currentSongNotifierProvider.notifier);
    final playlist = notifier.playlist;
    final currentIndex = notifier.currentSongIndex;

    final upcomingSongs = currentIndex >= 0 && currentIndex < playlist.length - 1
        ? playlist.sublist(currentIndex + 1)
        : <SongModel>[];

    final upcomingUserSongs = upcomingSongs.where((s) => !s.isAutoplay).toList();
    final upcomingAutoplaySongs = upcomingSongs.where((s) => s.isAutoplay).toList();
    final autoplayEnabled = ref.watch(autoplayEnabledProvider);
    final historySongs = currentIndex > 0 ? playlist.sublist(0, currentIndex) : <SongModel>[];

    final thumb = currentSong?.thumbnail_url ?? '';
    final playerScheme = ref.watch(playerSchemeProvider(thumb));

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: playerScheme),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;

          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.10),
                  scheme.surface,
                ],
                stops: const [0.0, 0.4],
              ),
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.keyboard_arrow_down, color: scheme.onSurface, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  'Play Queue',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
              ),
              body: playlist.isEmpty
                  ? Center(
                      child: Text(
                        'Queue is empty',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        // Currently Playing Section
                        if (currentSong != null) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Text(
                                'Now Playing',
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: getHighQualityThumbnail(currentSong.thumbnail_url),
                                  width: 48,
                                  height: 48,
                                  memCacheWidth: 96,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Container(
                                    width: 48,
                                    height: 48,
                                    color: scheme.surfaceContainerHigh,
                                    child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                              title: Text(
                                currentSong.song_name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                currentSong.artist +
                                    (currentSong.duration_seconds != null && currentSong.duration_seconds! > 0
                                        ? ' • ${_formatQueueDuration(currentSong.duration_seconds!)}'
                                        : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Icon(Icons.volume_up, color: scheme.primary),
                            ),
                          ),
                        ],

                        // User-queued Next In Queue Section
                        if (upcomingUserSongs.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 8.0),
                              child: Text(
                                'Playing Next',
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SliverReorderableList(
                            itemCount: upcomingUserSongs.length,
                            onReorder: (oldIdx, newIdx) {
                              final songToMove = upcomingUserSongs[oldIdx];
                              final actualOldIndex = playlist.indexOf(songToMove);
                              final targetSong = newIdx < upcomingUserSongs.length
                                  ? upcomingUserSongs[newIdx]
                                  : null;
                              final actualNewIndex = targetSong != null
                                  ? playlist.indexOf(targetSong)
                                  : playlist.length;
                              if (actualOldIndex != -1 && actualNewIndex != -1) {
                                notifier.reorderQueue(actualOldIndex, actualNewIndex);
                              }
                            },
                            itemBuilder: (context, index) {
                              final song = upcomingUserSongs[index];
                              final actualIndex = playlist.indexOf(song);

                              return ReorderableDelayedDragStartListener(
                                key: ValueKey('user-${song.id}-$actualIndex'),
                                index: index,
                                child: Dismissible(
                                  key: ValueKey('dismiss-user-${song.id}-$actualIndex'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20.0),
                                    color: scheme.errorContainer,
                                    child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                                  ),
                                  onDismissed: (direction) {
                                    notifier.removeSongFromQueue(actualIndex);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Removed "${song.song_name}" from queue')),
                                    );
                                  },
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNetworkImage(
                                        imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                        width: 44,
                                        height: 44,
                                        memCacheWidth: 96,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          width: 44,
                                          height: 44,
                                          color: scheme.surfaceContainerHigh,
                                          child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      song.song_name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      song.artist +
                                          (song.duration_seconds != null && song.duration_seconds! > 0
                                              ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                              : ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        // Autoplay Header & Toggle Section
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.all_inclusive, color: scheme.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Autoplay',
                                      style: textTheme.titleSmall?.copyWith(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Switch.adaptive(
                                  value: autoplayEnabled,
                                  onChanged: (val) {
                                    ref.read(autoplayEnabledProvider.notifier).setEnabled(val);
                                    if (!val) {
                                      notifier.removeAutoplayTracks();
                                    } else {
                                      notifier.checkAutoplay();
                                    }
                                  },
                                  activeThumbColor: scheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Autoplay Tracks List
                        if (autoplayEnabled && upcomingAutoplaySongs.isNotEmpty) ...[
                          SliverReorderableList(
                            itemCount: upcomingAutoplaySongs.length,
                            onReorder: (oldIdx, newIdx) {
                              final songToMove = upcomingAutoplaySongs[oldIdx];
                              final actualOldIndex = playlist.indexOf(songToMove);
                              final targetSong = newIdx < upcomingAutoplaySongs.length
                                  ? upcomingAutoplaySongs[newIdx]
                                  : null;
                              final actualNewIndex = targetSong != null
                                  ? playlist.indexOf(targetSong)
                                  : playlist.length;
                              if (actualOldIndex != -1 && actualNewIndex != -1) {
                                notifier.reorderQueue(actualOldIndex, actualNewIndex);
                              }
                            },
                            itemBuilder: (context, index) {
                              final song = upcomingAutoplaySongs[index];
                              final actualIndex = playlist.indexOf(song);

                              return ReorderableDelayedDragStartListener(
                                key: ValueKey('auto-${song.id}-$actualIndex'),
                                index: index,
                                child: Dismissible(
                                  key: ValueKey('dismiss-auto-${song.id}-$actualIndex'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20.0),
                                    color: scheme.errorContainer,
                                    child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                                  ),
                                  onDismissed: (direction) {
                                    notifier.removeSongFromQueue(actualIndex);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Removed "${song.song_name}" from queue')),
                                    );
                                  },
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNetworkImage(
                                        imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                        width: 44,
                                        height: 44,
                                        memCacheWidth: 96,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          width: 44,
                                          height: 44,
                                          color: scheme.surfaceContainerHigh,
                                          child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      song.song_name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      song.artist +
                                          (song.duration_seconds != null && song.duration_seconds! > 0
                                              ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                              : ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        // History Section
                        if (historySongs.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 8.0),
                              child: Text(
                                'Previously Played',
                                style: textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final song = historySongs[index];
                                return ListTile(
                                  onTap: () => notifier.playAtIndex(index),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Opacity(
                                      opacity: 0.6,
                                      child: CachedNetworkImage(
                                        imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                        width: 40,
                                        height: 40,
                                        memCacheWidth: 80,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          width: 40,
                                          height: 40,
                                          color: scheme.surfaceContainerHigh,
                                          child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    song.song_name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  subtitle: Text(
                                    song.artist +
                                        (song.duration_seconds != null && song.duration_seconds! > 0
                                            ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                            : ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    ),
                                  ),
                                );
                              },
                              childCount: historySongs.length,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  String _formatQueueDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
