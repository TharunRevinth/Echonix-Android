import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/utils.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/view/pages/upload_song_page.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:client/features/home/viewmodel/downloads_notifier.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        height: double.infinity,
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
          child: DefaultTabController(
            length: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
                  child: Text(
                    'Your Library',
                    style: textTheme.headlineMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: scheme.onSecondaryContainer,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  dividerColor: scheme.outlineVariant,
                  tabs: const [
                    Tab(text: 'Songs'),
                    Tab(text: 'Downloads'),
                    Tab(text: 'Playlists'),
                    Tab(text: 'Albums'),
                    Tab(text: 'Artists'),
                    Tab(text: 'Recently Played'),
                    Tab(text: 'Most Played'),
                    Tab(text: 'History'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _KeepAliveTab(child: _buildFavorites()),
                      _KeepAliveTab(child: _buildDownloads()),
                      _KeepAliveTab(child: _buildPlaylists()),
                      _KeepAliveTab(child: _buildSavedAlbums()),
                      _KeepAliveTab(child: _buildSavedArtists()),
                      _KeepAliveTab(child: _buildRecentlyPlayed()),
                      _KeepAliveTab(child: _buildMostPlayed()),
                      _KeepAliveTab(child: _buildPlaybackHistory()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteSong(SongModel song) async {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text('Delete Download', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
        content: Text('Are you sure you want to delete "${song.song_name}"?', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: textTheme.labelLarge?.copyWith(color: scheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final songFile = File(song.song_url);
        final jsonFile = File('${song.song_url}.json');
        if (await songFile.exists()) await songFile.delete();
        if (await jsonFile.exists()) await jsonFile.delete();
        final altAudio = File(song.song_url.endsWith('.mp3')
            ? song.song_url.replaceAll('.mp3', '.m4a')
            : song.song_url.replaceAll('.m4a', '.mp3'));
        final altJson = File('${altAudio.path}.json');
        if (await altAudio.exists()) await altAudio.delete();
        if (await altJson.exists()) await altJson.delete();
        PythonBackend.deleteDownloadedSong(song.id);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted "${song.song_name}"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting song: $e')),
          );
        }
      }
    }
  }

  void _deletePlaylist(String playlistName, List<SongModel> songs) async {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text('Delete Playlist', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
        content: Text('Are you sure you want to delete the playlist "$playlistName" and all its downloaded tracks?', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete All', style: textTheme.labelLarge?.copyWith(color: scheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (final song in songs) {
          final songFile = File(song.song_url);
          final jsonFile = File('${song.song_url}.json');
          if (await songFile.exists()) await songFile.delete();
          if (await jsonFile.exists()) await jsonFile.delete();
          final altAudio = File(song.song_url.endsWith('.mp3')
              ? song.song_url.replaceAll('.mp3', '.m4a')
              : song.song_url.replaceAll('.m4a', '.mp3'));
          final altJson = File('${altAudio.path}.json');
          if (await altAudio.exists()) await altAudio.delete();
          if (await altJson.exists()) await altJson.delete();
          PythonBackend.deleteDownloadedSong(song.id);
        }
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted playlist "$playlistName"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting playlist: $e')),
          );
        }
      }
    }
  }

  Widget _buildFavorites() {
    final likedSongIds = ref.watch(likedSongIdsProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ref.watch(favoriteSongsProvider).when(
          data: (data) {
            return ListView.builder(
              padding: EdgeInsets.only(bottom: dockHeight + 16),
              itemCount: data.length + 1,
              itemBuilder: (context, index) {
                if (index == data.length) {
                  return ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const UploadSongPage(),
                        ),
                      );
                    },
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(CupertinoIcons.plus, color: scheme.primary),
                    ),
                    title: Text(
                      'Upload New Song',
                      style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                    ),
                  );
                }

                final song = data[index];
                final isLiked = likedSongIds.contains(song.id);
                return ListTile(
                  onTap: () {
                    ref.read(currentSongNotifierProvider.notifier).updatePlaylist(data, index);
                  },
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: getHighQualityThumbnail(song.thumbnail_url),
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
                  trailing: IconButton(
                    icon: Icon(
                      isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                      color: isLiked ? scheme.tertiary : scheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      ref.read(likedSongIdsProvider.notifier).toggle(song);
                    },
                  ),
                );
              },
            );
          },
          error: (error, st) => Center(
            child: Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
          ),
          loading: () => const Loader(),
        );
  }

  Widget _buildPlaylists() {
    final playlists = ref.watch(localPlaylistsProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.builder(
      padding: EdgeInsets.only(bottom: dockHeight + 16),
      itemCount: playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            onTap: () => _showCreatePlaylistDialog(context),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(CupertinoIcons.plus, color: scheme.primary),
            ),
            title: Text(
              'Create Playlist',
              style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
            ),
          );
        }

        final playlist = playlists[index - 1];

        return ListTile(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => CustomPlaylistDetailsPage(
                  playlistId: playlist.id,
                  playlistName: playlist.name,
                ),
              ),
            );
          },
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PlaylistCoverWidget(playlist: playlist, size: 48),
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          subtitle: Text(
            '${playlist.songs.length} tracks • ${playlist.description.isNotEmpty ? playlist.description : 'Custom playlist'}${playlist.isCollaborative ? ' • Shared' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, color: scheme.error),
            onPressed: () {
              ref.read(localPlaylistsProvider.notifier).deletePlaylist(playlist.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted playlist "${playlist.name}"')),
              );
            },
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text('New Playlist', style: textTheme.titleLarge?.copyWith(color: scheme.onSurface)),
        content: TextField(
          controller: controller,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: scheme.primary)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: scheme.primary, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              ref.read(localPlaylistsProvider.notifier).createPlaylist(controller.text);
              Navigator.pop(context);
            },
            child: Text('Create', style: textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloads() {
    final dlState = ref.watch(downloadsProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(dlState.hashCode),
      future: PythonBackend.getDownloadedSongs(),
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
            child: Text(res?['error'] ?? 'Failed to load downloaded songs', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          );
        }

        final List songsList = res['songs'] ?? [];
        if (songsList.isEmpty) {
          return _buildEmptyState(
            icon: Icons.download_done_rounded,
            title: 'Nothing downloaded yet',
            subtitle: 'Songs and playlists you download will appear here',
          );
        }

        int totalBytes = 0;
        for (final s in songsList) {
          if (s is Map && s['size_bytes'] is num) {
            totalBytes += (s['size_bytes'] as num).toInt();
          }
        }
        final double mbUsed = totalBytes / (1024 * 1024);
        final String storageText = mbUsed >= 1024
            ? '${(mbUsed / 1024).toStringAsFixed(1)} GB'
            : '${mbUsed.toStringAsFixed(1)} MB';

        final Map<String, List<SongModel>> groupedPlaylists = {};
        final List<Map<String, dynamic>> individualSongsRaw = [];

        for (final s in songsList) {
          final playlistName = s['playlist_name'] as String? ?? '';
          final song = SongModel.fromBackend(Map<String, dynamic>.from(s as Map), hexCode: 'B388FF');
          if (playlistName.isNotEmpty) {
            groupedPlaylists.putIfAbsent(playlistName, () => []).add(song);
          } else {
            individualSongsRaw.add(Map<String, dynamic>.from(s));
          }
        }

        final playlistKeys = groupedPlaylists.keys.toList();
        final totalItemsCount = playlistKeys.length + individualSongsRaw.length + 1;

        return ListView.builder(
          padding: EdgeInsets.only(bottom: dockHeight + 16),
          itemCount: totalItemsCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${songsList.length} downloaded tracks',
                      style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      'Storage used: $storageText',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }

            final itemIdx = index - 1;
            if (itemIdx < playlistKeys.length) {
              final playlistName = playlistKeys[itemIdx];
              final playlistSongs = groupedPlaylists[playlistName]!;
              final firstSongThumb = playlistSongs.isNotEmpty ? playlistSongs.first.thumbnail_url : '';

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: firstSongThumb.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: firstSongThumb,
                          width: 48,
                          height: 48,
                          memCacheWidth: 96,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            width: 48,
                            height: 48,
                            color: scheme.surfaceContainerHigh,
                            child: Icon(Icons.playlist_play, color: scheme.onSurfaceVariant),
                          ),
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          color: scheme.surfaceContainerHigh,
                          child: Icon(Icons.playlist_play, color: scheme.onSurfaceVariant),
                        ),
                ),
                title: Text(playlistName, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                subtitle: Text('${playlistSongs.length} tracks (Downloaded Playlist)', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      onPressed: () => _deletePlaylist(playlistName, playlistSongs),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DownloadedPlaylistPage(title: playlistName, songs: playlistSongs),
                    ),
                  ).then((_) => setState(() {}));
                },
              );
            } else {
              final songIndex = itemIdx - playlistKeys.length;
              final rawSong = individualSongsRaw[songIndex];
              final song = SongModel.fromBackend(Map<String, dynamic>.from(rawSong), hexCode: 'B388FF');
              final hasLyrics = rawSong['lyrics_data'] != null;
              final sizeBytes = (rawSong['size_bytes'] as num?)?.toInt() ?? 0;
              final songSizeMb = sizeBytes > 0 ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '';

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: getHighQualityThumbnail(song.thumbnail_url),
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
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        song.song_name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                      ),
                    ),
                    if (hasLyrics)
                      Tooltip(
                        message: 'Offline lyrics available',
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6.0),
                          child: Icon(Icons.lyrics, color: scheme.primary, size: 16),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  songSizeMb.isNotEmpty ? '${song.artist} • $songSizeMb' : song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                trailing: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                  color: scheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (value) async {
                    if (value == 'delete') {
                      _deleteSong(song);
                    } else if (value == 'redownload_lyrics') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrying lyrics download...')));
                      final res = await PythonBackend.redownloadLyrics(song.id, song.song_name, song.artist);
                      if (res['success'] == true) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lyrics downloaded successfully!')));
                        }
                        setState(() {});
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res['error'] ?? 'Lyrics not found'}')));
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'redownload_lyrics',
                      child: Text(hasLyrics ? 'Refresh Lyrics' : 'Download Lyrics', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Download', style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
                    ),
                  ],
                ),
                onTap: () {
                  final mappedSongs = individualSongsRaw
                      .map((raw) => SongModel.fromBackend(Map<String, dynamic>.from(raw), hexCode: 'B388FF'))
                      .toList();
                  ref.read(currentSongNotifierProvider.notifier).updatePlaylist(mappedSongs, songIndex);
                },
              );
            }
          },
        );
      },
    );
  }

  Widget _buildRecentlyPlayed() {
    final songs = ref.watch(recentlyPlayedProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (songs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No recently played songs',
        subtitle: 'Songs you play will appear here',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: dockHeight + 16),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: getHighQualityThumbnail(song.thumbnail_url),
              width: 44,
              height: 44,
              memCacheWidth: 88,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                width: 44,
                height: 44,
                color: scheme.surfaceContainerHigh,
                child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          title: Text(song.song_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
        );
      },
    );
  }

  Widget _buildPlaybackHistory() {
    final history = ref.watch(listeningHistoryProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (history.isEmpty) {
      return _buildEmptyState(
        icon: Icons.access_time_rounded,
        title: 'No listening history',
        subtitle: 'Your listening activity will be recorded here',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${history.length} plays recorded', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              TextButton(
                onPressed: () {
                  ref.read(homeLocalRepositoryProvider).clearListeningHistory();
                  setState(() {});
                },
                child: Text('Clear', style: textTheme.labelLarge?.copyWith(color: scheme.error)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(bottom: dockHeight + 16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              final song = SongModel.fromMap(Map<String, dynamic>.from(item['song']));
              final ts = item['timestamp'] as int? ?? 0;
              final timeStr = _formatTimestamp(ts);

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                    width: 44,
                    height: 44,
                    memCacheWidth: 88,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 44,
                      height: 44,
                      color: scheme.surfaceContainerHigh,
                      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                title: Text(song.song_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                subtitle: Text('${song.artist} • $timeStr', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMostPlayed() {
    final localRepo = ref.watch(homeLocalRepositoryProvider);
    final allKnown = localRepo.getRecentlyPlayed();
    final mostPlayed = localRepo.getMostPlayedSongs(allKnown);
    final playCounts = localRepo.getPlayCounts();
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (mostPlayed.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Complete playback to track counts',
        subtitle: 'Play tracks repeatedly to see your favorites ranked here',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: dockHeight + 16),
      itemCount: mostPlayed.length,
      itemBuilder: (context, index) {
        final song = mostPlayed[index];
        final count = playCounts[song.id] ?? 0;
        return ListTile(
          leading: Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              '#${index + 1}',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(song.song_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
          subtitle: Text('${song.artist} • $count plays', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
        );
      },
    );
  }

  Widget _buildSavedAlbums() {
    final albums = ref.watch(savedAlbumsProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (albums.isEmpty) {
      return _buildEmptyState(
        icon: Icons.album_rounded,
        title: 'No saved albums',
        subtitle: 'Save albums to access them quickly here',
      );
    }
    return GridView.builder(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: dockHeight + 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PlaylistDetailsPage(
                  id: album['id'] ?? '',
                  title: album['title'] ?? '',
                  thumbnailUrl: album['thumbnail'] ?? '',
                  isAlbum: true,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: getHighQualityThumbnail(album['thumbnail'] ?? ''),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    memCacheWidth: 240,
                    errorWidget: (context, url, error) => Container(
                      color: scheme.surfaceContainerHigh,
                      child: Icon(Icons.album_rounded, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.bold),
              ),
              Text(
                album['artist'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSavedArtists() {
    final artists = ref.watch(savedArtistsProvider);
    final dockHeight = ref.watch(dockHeightProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (artists.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_rounded,
        title: 'No followed artists',
        subtitle: 'Follow artists to see their releases here',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: dockHeight + 16),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          onTap: () {
            ref.read(searchQueryProvider.notifier).state = artist['name'] ?? '';
            ref.read(homeTabIndexProvider.notifier).state = 1;
          },
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: CachedNetworkImage(
              imageUrl: getHighQualityThumbnail(artist['thumbnail'] ?? ''),
              width: 48,
              height: 48,
              memCacheWidth: 96,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                width: 48,
                height: 48,
                color: scheme.surfaceContainerHigh,
                child: Icon(Icons.person, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          title: Text(artist['name'] ?? '', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
          trailing: IconButton(
            icon: Icon(Icons.check_circle, color: scheme.primary),
            onPressed: () {
              ref.read(homeLocalRepositoryProvider).removeArtist(artist['id'] ?? '');
              setState(() {});
            },
          ),
        );
      },
    );
  }

  String _formatTimestamp(int ms) {
    if (ms == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} mins ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// -----------------------------------------------------------------------------
// Custom Playlist Details Page Widget
// -----------------------------------------------------------------------------
class CustomPlaylistDetailsPage extends ConsumerStatefulWidget {
  final String? playlistId;
  final String playlistName;

  const CustomPlaylistDetailsPage({super.key, this.playlistId, required this.playlistName});

  @override
  ConsumerState<CustomPlaylistDetailsPage> createState() => _CustomPlaylistDetailsPageState();
}

class _CustomPlaylistDetailsPageState extends ConsumerState<CustomPlaylistDetailsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localPlaylistsProvider.notifier).fetchRemoteTracksIfEmpty(widget.playlistId ?? widget.playlistName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider);
    final playlist = playlists.firstWhere(
      (p) => (widget.playlistId != null && p.id == widget.playlistId) || p.name == widget.playlistName,
      orElse: () => CustomPlaylist(id: widget.playlistId ?? '', name: widget.playlistName, songs: []),
    );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: scheme.onSurface),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.edit, color: scheme.onSurface),
                      onPressed: () => _showEditPlaylistDialog(context, playlist),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PlaylistCoverWidget(playlist: playlist, size: 110),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (playlist.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              playlist.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${playlist.songs.length} songs ${playlist.isCollaborative ? '• Shared' : ''}',
                            style: textTheme.labelSmall?.copyWith(color: scheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (playlist.songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(currentSongNotifierProvider.notifier).updatePlaylist(playlist.songs, 0);
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play All'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final shuffled = List<SongModel>.from(playlist.songs)..shuffle();
                            ref.read(currentSongNotifierProvider.notifier).updatePlaylist(shuffled, 0);
                          },
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: playlist.songs.isEmpty
                  ? Center(
                      child: Text(
                        'No songs in this playlist yet.\nSearch for songs to add them!',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: playlist.songs.length,
                      onReorder: (oldIndex, newIndex) {
                        ref.read(localPlaylistsProvider.notifier).reorderSongInPlaylist(playlist.id, oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final song = playlist.songs[index];
                        return ListTile(
                          key: ValueKey(song.id + index.toString()),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                              width: 44,
                              height: 44,
                              memCacheWidth: 88,
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
                              IconButton(
                                icon: Icon(Icons.download, color: scheme.onSurfaceVariant, size: 20),
                                onPressed: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Downloading "${song.song_name}" in background...')),
                                  );
                                  await PythonBackend.downloadSong(
                                    song.id,
                                    song.song_name,
                                    song.artist,
                                    song.thumbnail_url,
                                    playlist.name,
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.remove_circle_outline, color: scheme.error, size: 20),
                                onPressed: () {
                                  ref.read(localPlaylistsProvider.notifier).removeSongFromPlaylist(playlist.id, song.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Removed "${song.song_name}"')),
                                  );
                                },
                              ),
                              Icon(Icons.drag_handle, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                            ],
                          ),
                          onTap: () {
                            ref.read(currentSongNotifierProvider.notifier).updatePlaylist(playlist.songs, index);
                          },
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

  void _showEditPlaylistDialog(BuildContext context, CustomPlaylist playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);
    String? coverPath = playlist.customCoverPath;
    bool isCollab = playlist.isCollaborative;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit Playlist Details', style: textTheme.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    decoration: InputDecoration(labelText: 'Name', labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    decoration: InputDecoration(labelText: 'Description', labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('Custom Cover Art:', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(type: FileType.image);
                          if (result != null && result.files.single.path != null) {
                            setModalState(() {
                              coverPath = result.files.single.path;
                            });
                          }
                        },
                        child: const Text('Pick Image'),
                      ),
                      if (coverPath != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.check_circle, color: scheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('Collaborative Playlist', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                    subtitle: Text('Allow other users to edit', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    value: isCollab,
                    onChanged: (val) {
                      setModalState(() {
                        isCollab = val;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          if (newName.isNotEmpty && newName != playlist.name) {
                            await ref.read(localPlaylistsProvider.notifier).renamePlaylist(playlist.id, newName);
                          }
                          await ref.read(localPlaylistsProvider.notifier).updatePlaylistDetails(
                                playlist.id,
                                name: newName.isNotEmpty ? newName : null,
                                description: descController.text.trim(),
                                customCoverPath: coverPath,
                                isCollaborative: isCollab,
                              );
                          if (context.mounted) Navigator.pop(context);
                          setState(() {});
                        },
                        child: const Text('Save Details'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Downloaded Playlist Page Widget
// -----------------------------------------------------------------------------
class DownloadedPlaylistPage extends ConsumerStatefulWidget {
  final String title;
  final List<SongModel> songs;

  const DownloadedPlaylistPage({
    super.key,
    required this.title,
    required this.songs,
  });

  @override
  ConsumerState<DownloadedPlaylistPage> createState() => _DownloadedPlaylistPageState();
}

class _DownloadedPlaylistPageState extends ConsumerState<DownloadedPlaylistPage> {
  late List<SongModel> _songs;

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.songs);
  }

  void _deleteSong(SongModel song) async {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text('Delete Download', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
        content: Text('Are you sure you want to delete "${song.song_name}"?', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: textTheme.labelLarge?.copyWith(color: scheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final mp3File = File(song.song_url);
        final jsonFile = File('${song.song_url}.json');
        if (await mp3File.exists()) await mp3File.delete();
        if (await jsonFile.exists()) await jsonFile.delete();
        setState(() {
          _songs.remove(song);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted "${song.song_name}"')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting song: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: scheme.onSurface)),
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
          child: Column(
            children: [
              if (_songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FilledButton.icon(
                    onPressed: () {
                      ref.read(currentSongNotifierProvider.notifier).updatePlaylist(_songs, 0);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play All'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: song.thumbnail_url,
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
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                        onPressed: () => _deleteSong(song),
                      ),
                      onTap: () {
                        ref.read(currentSongNotifierProvider.notifier).updatePlaylist(_songs, index);
                      },
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

// -----------------------------------------------------------------------------
// Playlist Cover Art / Collage Widget
// -----------------------------------------------------------------------------
class PlaylistCoverWidget extends StatelessWidget {
  final CustomPlaylist playlist;
  final double size;

  const PlaylistCoverWidget({super.key, required this.playlist, this.size = 140});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (playlist.customCoverPath != null && playlist.customCoverPath!.isNotEmpty) {
      final file = File(playlist.customCoverPath!);
      if (file.existsSync()) {
        return Image.file(file, width: size, height: size, fit: BoxFit.cover);
      }
    }

    if (playlist.songs.length >= 4) {
      return SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: playlist.songs.take(4).map((song) {
            return CachedNetworkImage(
              imageUrl: song.thumbnail_url,
              memCacheWidth: size.toInt(),
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(color: scheme.surfaceContainerHigh),
            );
          }).toList(),
        ),
      );
    }

    if (playlist.songs.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: playlist.songs.first.thumbnail_url,
        width: size,
        height: size,
        memCacheWidth: (size * 2).toInt(),
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => Container(
          color: scheme.surfaceContainerHigh,
          child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.playlist_play, color: scheme.onSurfaceVariant, size: 28),
    );
  }
}
