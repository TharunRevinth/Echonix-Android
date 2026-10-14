import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
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

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF180828),
              Color(0xFF090310),
              Colors.black,
            ],
            stops: [0.0, 0.4, 1.0],
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
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final res = snapshot.data;
              if (res == null || res['success'] != true) {
                return Center(
                  child: Text(res?['error'] ?? 'Failed to load details'),
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
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: thumbnailUrl,
                              width: 200,
                              height: 200,
                              memCacheWidth: 400,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.music_note, size: 100),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () {
                                        ref
                                            .read(currentSongNotifierProvider.notifier)
                                            .updatePlaylist(songs, 0);
                                      },
                                icon: const Icon(Icons.play_arrow, color: Colors.black),
                                label: const Text(
                                  'Play All',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: songs.isEmpty
                                    ? null
                                    : () async {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Downloading ${songs.length} tracks in background...',
                                            ),
                                          ),
                                        );
                                        for (final song in songs) {
                                          await PythonBackend.downloadSong(
                                            song.id,
                                            song.song_name,
                                            song.artist,
                                            song.thumbnail_url,
                                            title,
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.download, color: Colors.white),
                                label: const Text(
                                  'Download All',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
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
                          leading: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          title: Text(
                            song.song_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.grey),
                            color: const Color(0xFF1E1E1E),
                            onSelected: (value) async {
                              if (value == 'download') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Downloading "${song.song_name}" in background...'),
                                  ),
                                );
                                final res = await PythonBackend.downloadSong(
                                  song.id,
                                  song.song_name,
                                  song.artist,
                                  song.thumbnail_url,
                                );
                                if (res['success'] != true) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to download: ${res['error']}'),
                                    ),
                                  );
                                }
                              } else if (value == 'playlist') {
                                _showAddToPlaylistDialog(context, ref, song);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'playlist',
                                child: Text('Add to Playlist...', style: TextStyle(color: Colors.white)),
                              ),
                              const PopupMenuItem(
                                value: 'download',
                                child: Text('Download', style: TextStyle(color: Colors.white)),
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, SongModel song) {
    showAddToPlaylistDialog(context, ref, song);
  }
}
