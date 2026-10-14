import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/utils.dart';
import 'package:flutter/cupertino.dart';
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

    // Up next list (songs after the currently playing song)
    final upcomingSongs = currentIndex >= 0 && currentIndex < playlist.length - 1
        ? playlist.sublist(currentIndex + 1)
        : <SongModel>[];

    final upcomingUserSongs = upcomingSongs.where((s) => !s.isAutoplay).toList();
    final upcomingAutoplaySongs = upcomingSongs.where((s) => s.isAutoplay).toList();
    final autoplayEnabled = ref.watch(autoplayEnabledProvider);

    // History queue list (songs played before)
    final historySongs = currentIndex > 0 ? playlist.sublist(0, currentIndex) : [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Play Queue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF150A22),
              Color(0xFF0C0614),
              Colors.black,
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: playlist.isEmpty
            ? const Center(
                child: Text('Queue is empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
              )
            : CustomScrollView(
                slivers: [
                  // Currently Playing Section
                  if (currentSong != null) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Text(
                          'Now Playing',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: getHighQualityThumbnail(currentSong.thumbnail_url),
                            width: 50,
                            height: 50,
                            memCacheWidth: 100,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.music_note, color: Colors.white),
                          ),
                        ),
                        title: Text(
                          currentSong.song_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          currentSong.artist +
                              (currentSong.duration_seconds != null && currentSong.duration_seconds! > 0
                                  ? ' • ${_formatQueueDuration(currentSong.duration_seconds!)}'
                                  : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: const Icon(Icons.volume_up, color: Pallete.borderColor),
                      ),
                    ),
                  ],

                  // User-queued Next In Queue Section
                  if (upcomingUserSongs.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                        child: Text(
                          'Next In Queue',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                              color: Colors.redAccent.withOpacity(0.8),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (direction) {
                              notifier.removeSongFromQueue(actualIndex);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Removed "${song.song_name}" from queue')),
                              );
                            },
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                  width: 48,
                                  height: 48,
                                  memCacheWidth: 96,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.music_note, color: Colors.white),
                                ),
                              ),
                              title: Text(
                                song.song_name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                song.artist +
                                    (song.duration_seconds != null && song.duration_seconds! > 0
                                        ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                        : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              trailing: const Icon(Icons.drag_handle_rounded, color: Colors.white30),
                            ),
                          ),
                        );
                      },
                    ),
                  ],

                  // Autoplay Header & Toggle Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.all_inclusive, color: Colors.blueAccent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Autoplay',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Transform.scale(
                            scale: 0.85,
                            child: Switch.adaptive(
                              value: autoplayEnabled,
                              onChanged: (val) {
                                ref.read(autoplayEnabledProvider.notifier).setEnabled(val);
                                if (!val) {
                                  notifier.removeAutoplayTracks();
                                } else {
                                  notifier.checkAutoplay();
                                }
                              },
                              activeColor: Colors.blueAccent,
                            ),
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
                              color: Colors.redAccent.withOpacity(0.8),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (direction) {
                              notifier.removeSongFromQueue(actualIndex);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Removed "${song.song_name}" from queue')),
                              );
                            },
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                  width: 48,
                                  height: 48,
                                  memCacheWidth: 96,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.music_note, color: Colors.white),
                                ),
                              ),
                              title: Text(
                                song.song_name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                song.artist +
                                    (song.duration_seconds != null && song.duration_seconds! > 0
                                        ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                        : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              trailing: const Icon(Icons.drag_handle_rounded, color: Colors.white30),
                            ),
                          ),
                        );
                      },
                    ),
                  ],

                  // History Section
                  if (historySongs.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
                        child: Text(
                          'Previously Played',
                          style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 14),
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
                              borderRadius: BorderRadius.circular(6),
                              child: Opacity(
                                opacity: 0.5,
                                child: CachedNetworkImage(
                                  imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                                  width: 40,
                                  height: 40,
                                  memCacheWidth: 80,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.music_note, color: Colors.white),
                                ),
                              ),
                            ),
                            title: Text(
                              song.song_name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 14),
                            ),
                            subtitle: Text(
                              song.artist +
                                  (song.duration_seconds != null && song.duration_seconds! > 0
                                      ? ' • ${_formatQueueDuration(song.duration_seconds!)}'
                                      : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
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
  }

  String _formatQueueDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
