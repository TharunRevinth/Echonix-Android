import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/viewmodel/downloads_notifier.dart';
import 'package:client/core/widgets/add_to_playlist_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaylistDetailsPage extends ConsumerWidget {
  final String id;
  final String title;
  final String thumbnailUrl;
  final bool isAlbum;

  const PlaylistDetailsPage({
    super.key,
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.isAlbum,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Future<Map<String, dynamic>> detailsFuture = isAlbum
        ? PythonBackend.getAlbumDetails(id)
        : PythonBackend.getPlaylistDetails(id);

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: scheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
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
        child: SafeArea(
          bottom: false,
          child: FutureBuilder<Map<String, dynamic>>(
            future: detailsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}', style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
                );
              }

              final res = snapshot.data;
              if (res == null || res['success'] != true) {
                return Center(
                  child: Text(res?['error'] ?? 'Failed to load details', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                );
              }

              final description = res['description'] as String? ?? res['artist'] as String? ?? '';
              final List tracksList = res['tracks'] ?? [];
              final List<SongModel> songs = tracksList
                  .map(
                    (s) {
                      final m = Map<String, dynamic>.from(s as Map);
                      if ((m['thumbnail'] == null || m['thumbnail'].toString().trim().isEmpty) &&
                          (m['thumbnails'] == null || (m['thumbnails'] as List).isEmpty)) {
                        m['thumbnail'] = thumbnailUrl;
                      }
                      return SongModel.fromBackend(m, hexCode: 'B388FF');
                    },
                  )
                  .toList();

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(
                              imageUrl: thumbnailUrl,
                              width: 180,
                              height: 180,
                              memCacheWidth: 360,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                width: 180,
                                height: 180,
                                color: scheme.surfaceContainerHigh,
                                child: Icon(Icons.music_note, color: scheme.onSurfaceVariant, size: 80),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        ref
                                            .read(currentSongNotifierProvider.notifier)
                                            .updatePlaylist(songs, 0);
                                      },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play All'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        for (final song in songs) {
                                          ref.read(downloadsProvider.notifier).startDownloading(song);
                                        }
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Queued ${songs.length} tracks for download',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.download),
                                label: const Text('Download All'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = songs[index];
                        return ListTile(
                          leading: SizedBox(
                            width: 28,
                            child: Align(
                              alignment: Alignment.center,
                              child: Text(
                                '${index + 1}',
                                style: textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                          title: Text(
                            song.song_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                          ),
                          subtitle: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DownloadButton(song: song, size: 22, color: scheme.onSurfaceVariant),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                                color: scheme.surfaceContainerHigh,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                onSelected: (value) {
                                  if (value == 'download') {
                                    ref.read(downloadsProvider.notifier).startDownloading(song);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Download queued: "${song.song_name}"'),
                                      ),
                                    );
                                  } else if (value == 'playlist') {
                                    showAddToPlaylistDialog(context, ref, song);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'playlist',
                                    child: Text('Add to Playlist...', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                                  ),
                                  PopupMenuItem(
                                    value: 'download',
                                    child: Text('Download', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () {
                            ref
                                .read(currentSongNotifierProvider.notifier)
                                .updatePlaylist(songs, index);
                          },
                        );
                      },
                      childCount: songs.length,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
