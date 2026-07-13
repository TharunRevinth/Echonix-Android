import 'dart:convert';
import 'dart:io';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/utils.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/view/pages/upload_song_page.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _selectedTab = 0; 
  // 0: Favorites, 1: Playlists, 2: Downloads, 3: Recently Played, 4: History, 5: Most Played, 6: Albums, 7: Artists

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        height: double.infinity,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
                child: Text(
                  'Your Library',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              // Scrolling category selector chips
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _buildTabChip(0, 'Favorites'),
                    _buildTabChip(1, 'Playlists'),
                    _buildTabChip(2, 'Downloads'),
                    _buildTabChip(3, 'Recent'),
                    _buildTabChip(4, 'History'),
                    _buildTabChip(5, 'Most Played'),
                    _buildTabChip(6, 'Saved Albums'),
                    _buildTabChip(7, 'Followed Artists'),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: _buildSelectedTabContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabChip(int index, String label) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? Pallete.borderColor : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.purpleAccent : Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildFavorites();
      case 1:
        return _buildPlaylists();
      case 2:
        return _buildDownloads();
      case 3:
        return _buildRecentlyPlayed();
      case 4:
        return _buildPlaybackHistory();
      case 5:
        return _buildMostPlayed();
      case 6:
        return _buildSavedAlbums();
      case 7:
        return _buildSavedArtists();
      default:
        return const SizedBox();
    }
  }

  void _deleteSong(SongModel song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Download', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${song.song_name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${song.song_name}"')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting song: $e')),
        );
      }
    }
  }

  void _deletePlaylist(String playlistName, List<SongModel> songs) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete the playlist "$playlistName" and all its downloaded tracks?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (final song in songs) {
          final mp3File = File(song.song_url);
          final jsonFile = File('${song.song_url}.json');
          if (await mp3File.exists()) await mp3File.delete();
          if (await jsonFile.exists()) await jsonFile.delete();
        }
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted playlist "$playlistName"')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting playlist: $e')),
        );
      }
    }
  }

  Widget _buildFavorites() {
    return ref.watch(getFavSongsProvider).when(
          data: (data) {
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
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
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Icon(CupertinoIcons.plus, color: Colors.white),
                    ),
                    title: const Text(
                      'Upload New Song',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  );
                }

                final song = data[index];
                return ListTile(
                  onTap: () {
                    ref.read(currentSongNotifierProvider.notifier).updatePlaylist(data, index);
                  },
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      getHighQualityThumbnail(song.thumbnail_url),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.music_note, size: 50),
                    ),
                  ),
                  title: Text(
                    song.song_name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  subtitle: Text(
                    song.artist,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.heart_fill, color: Colors.redAccent),
                    onPressed: () {
                      ref.read(homeViewModelProvider.notifier).favSong(songId: song.id);
                    },
                  ),
                );
              },
            );
          },
          error: (error, st) => Center(child: Text(error.toString(), style: const TextStyle(color: Colors.white))),
          loading: () => const Loader(),
        );
  }

  Widget _buildPlaylists() {
    final playlists = ref.watch(localPlaylistsProvider);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            onTap: () => _showCreatePlaylistDialog(context),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(CupertinoIcons.plus, color: Colors.white),
            ),
            title: const Text(
              'Create Playlist',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          );
        }

        final playlist = playlists[index - 1];

        return ListTile(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => CustomPlaylistDetailsPage(playlistName: playlist.name),
              ),
            );
          },
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: PlaylistCoverWidget(playlist: playlist, size: 50),
          ),
          title: Text(
            playlist.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          subtitle: Text(
            '${playlist.songs.length} tracks • ${playlist.description.isNotEmpty ? playlist.description : 'Custom playlist'}${playlist.isCollaborative ? ' • Shared' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              ref.read(localPlaylistsProvider.notifier).deletePlaylist(playlist.name);
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              ref.read(localPlaylistsProvider.notifier).createPlaylist(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Create', style: TextStyle(color: Colors.purpleAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloads() {
    return FutureBuilder<Map<String, dynamic>>(
      future: PythonBackend.getDownloadedSongs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Loader();
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
        }
        final res = snapshot.data;
        if (res == null || res['success'] != true) {
          return Center(
            child: Text(res?['error'] ?? 'Failed to load downloaded songs', style: const TextStyle(color: Colors.grey)),
          );
        }

        final List songsList = res['songs'] ?? [];
        if (songsList.isEmpty) {
          return const Center(
            child: Text('No downloaded songs found.', style: TextStyle(color: Colors.grey)),
          );
        }

        final Map<String, List<SongModel>> groupedPlaylists = {};
        final List<Map<String, dynamic>> individualSongsRaw = [];

        for (final s in songsList) {
          final playlistName = s['playlist_name'] as String? ?? '';
          final song = SongModel(
            id: s['id'] ?? '',
            song_name: s['title'] ?? '',
            artist: s['artist'] ?? '',
            thumbnail_url: s['thumbnail_url'] ?? 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=150',
            song_url: s['path'] ?? '',
            hex_code: 'B388FF',
          );
          if (playlistName.isNotEmpty) {
            groupedPlaylists.putIfAbsent(playlistName, () => []).add(song);
          } else {
            individualSongsRaw.add(s);
          }
        }

        final playlistKeys = groupedPlaylists.keys.toList();
        final totalItemsCount = playlistKeys.length + individualSongsRaw.length;

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 110),
          itemCount: totalItemsCount,
          itemBuilder: (context, index) {
            if (index < playlistKeys.length) {
              final playlistName = playlistKeys[index];
              final playlistSongs = groupedPlaylists[playlistName]!;
              final firstSongThumb = playlistSongs.isNotEmpty ? playlistSongs.first.thumbnail_url : '';

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: firstSongThumb.isNotEmpty
                      ? Image.network(firstSongThumb, width: 50, height: 50, fit: BoxFit.cover)
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.white.withOpacity(0.05),
                          child: const Icon(Icons.playlist_play, color: Colors.white70),
                        ),
                ),
                title: Text(playlistName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                subtitle: Text('${playlistSongs.length} tracks (Downloaded Playlist)', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _deletePlaylist(playlistName, playlistSongs),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
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
              final songIndex = index - playlistKeys.length;
              final rawSong = individualSongsRaw[songIndex];
              final song = SongModel(
                id: rawSong['id'] ?? '',
                song_name: rawSong['title'] ?? '',
                artist: rawSong['artist'] ?? '',
                thumbnail_url: rawSong['thumbnail_url'] ?? '',
                song_url: rawSong['path'] ?? '',
                hex_code: 'B388FF',
              );
              final hasLyrics = rawSong['lyrics_data'] != null;

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    getHighQualityThumbnail(song.thumbnail_url),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, size: 50),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        song.song_name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    if (hasLyrics)
                      const Tooltip(
                        message: 'Offline lyrics available',
                        child: Padding(
                          padding: EdgeInsets.only(left: 6.0),
                          child: Icon(Icons.lyrics, color: Colors.greenAccent, size: 16),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(song.artist, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  color: const Color(0xFF1E1E1E),
                  onSelected: (value) async {
                    if (value == 'delete') {
                      _deleteSong(song);
                    } else if (value == 'redownload_lyrics') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrying lyrics download...')));
                      final res = await PythonBackend.redownloadLyrics(song.id, song.song_name, song.artist);
                      if (res['success'] == true) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lyrics downloaded successfully!')));
                        setState(() {});
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${res['error'] ?? 'Lyrics not found'}')));
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'redownload_lyrics',
                      child: Text(hasLyrics ? 'Refresh Lyrics' : 'Download Lyrics', style: const TextStyle(color: Colors.white)),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Download', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
                onTap: () {
                  final mappedSongs = individualSongsRaw.map((raw) => SongModel(
                    id: raw['id'] ?? '',
                    song_name: raw['title'] ?? '',
                    artist: raw['artist'] ?? '',
                    thumbnail_url: raw['thumbnail_url'] ?? '',
                    song_url: raw['path'] ?? '',
                    hex_code: 'B388FF',
                  )).toList();
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
    if (songs.isEmpty) {
      return const Center(child: Text('No recently played songs', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(getHighQualityThumbnail(song.thumbnail_url), width: 44, height: 44, fit: BoxFit.cover),
          ),
          title: Text(song.song_name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(song.artist, style: const TextStyle(color: Colors.grey)),
          onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
        );
      },
    );
  }

  Widget _buildPlaybackHistory() {
    final history = ref.watch(listeningHistoryProvider);
    if (history.isEmpty) {
      return const Center(child: Text('No listening history', style: TextStyle(color: Colors.grey)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${history.length} plays recorded', style: const TextStyle(color: Colors.white54)),
              TextButton(
                onPressed: () {
                  ref.read(homeLocalRepositoryProvider).clearListeningHistory();
                  setState(() {});
                },
                child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 110),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              final song = SongModel.fromMap(Map<String, dynamic>.from(item['song']));
              final ts = item['timestamp'] as int? ?? 0;
              final timeStr = _formatTimestamp(ts);

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(getHighQualityThumbnail(song.thumbnail_url), width: 44, height: 44, fit: BoxFit.cover),
                ),
                title: Text(song.song_name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${song.artist} • $timeStr', style: const TextStyle(color: Colors.grey)),
                onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMostPlayed() {
    // Collect all unique songs from recently played and other segments to cross-reference counts
    final localRepo = ref.watch(homeLocalRepositoryProvider);
    final allKnown = localRepo.getRecentlyPlayed();
    final mostPlayed = localRepo.getMostPlayedSongs(allKnown);
    final playCounts = localRepo.getPlayCounts();

    if (mostPlayed.isEmpty) {
      return const Center(child: Text('Complete playback to track counts', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: mostPlayed.length,
      itemBuilder: (context, index) {
        final song = mostPlayed[index];
        final count = playCounts[song.id] ?? 0;
        return ListTile(
          leading: Container(
            width: 32,
            alignment: Alignment.center,
            child: Text('#${index + 1}', style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          title: Text(song.song_name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text('${song.artist} • $count plays', style: const TextStyle(color: Colors.grey)),
          onTap: () => ref.read(currentSongNotifierProvider.notifier).updateSong(song),
        );
      },
    );
  }

  Widget _buildSavedAlbums() {
    final albums = ref.watch(savedAlbumsProvider);
    if (albums.isEmpty) {
      return const Center(child: Text('No saved albums', style: TextStyle(color: Colors.grey)));
    }
    return GridView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 110),
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
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    getHighQualityThumbnail(album['thumbnail'] ?? ''),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                album['artist'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSavedArtists() {
    final artists = ref.watch(savedArtistsProvider);
    if (artists.isEmpty) {
      return const Center(child: Text('No followed artists', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          onTap: () {
            // Push search query to search and navigate
            ref.read(searchQueryProvider.notifier).state = artist['name'] ?? '';
            // Switch navigation tab to Search tab (typically index 1 or triggered by router)
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Searching for "${artist['name']}"...')));
          },
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Image.network(
              getHighQualityThumbnail(artist['thumbnail'] ?? ''),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10),
            ),
          ),
          title: Text(artist['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.purpleAccent),
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
// Custom Playlist Details Page Widget (Draggable reordering, custom covers, descriptions, and collaboration)
// -----------------------------------------------------------------------------
class CustomPlaylistDetailsPage extends ConsumerStatefulWidget {
  final String playlistName;

  const CustomPlaylistDetailsPage({super.key, required this.playlistName});

  @override
  ConsumerState<CustomPlaylistDetailsPage> createState() => _CustomPlaylistDetailsPageState();
}

class _CustomPlaylistDetailsPageState extends ConsumerState<CustomPlaylistDetailsPage> {
  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(localPlaylistsProvider);
    final playlist = playlists.firstWhere(
      (p) => p.name == widget.playlistName,
      orElse: () => CustomPlaylist(name: widget.playlistName, songs: []),
    );

    return Scaffold(
      backgroundColor: Colors.black,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customized Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
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
                      borderRadius: BorderRadius.circular(12),
                      child: PlaylistCoverWidget(playlist: playlist, size: 120),
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
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          if (playlist.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              playlist.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${playlist.songs.length} songs ${playlist.isCollaborative ? '• Shared' : ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600),
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(currentSongNotifierProvider.notifier).updatePlaylist(playlist.songs, 0);
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.black),
                    label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                ),

              Expanded(
                child: playlist.songs.isEmpty
                    ? const Center(
                        child: Text(
                          'No songs in this playlist yet.\nSearch for songs to add them!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: playlist.songs.length,
                        onReorder: (oldIndex, newIndex) {
                          ref.read(localPlaylistsProvider.notifier).reorderSongInPlaylist(playlist.name, oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final song = playlist.songs[index];
                          return ListTile(
                            key: ValueKey(song.id + index.toString()),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                getHighQualityThumbnail(song.thumbnail_url),
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.music_note, size: 44),
                              ),
                            ),
                            title: Text(
                              song.song_name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                            ),
                            subtitle: Text(
                              song.artist,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () {
                                    ref.read(localPlaylistsProvider.notifier).removeSongFromPlaylist(playlist.name, song.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Removed "${song.song_name}"')),
                                    );
                                  },
                                ),
                                const Icon(Icons.drag_handle, color: Colors.white30),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  const Text('Edit Playlist Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('Custom Cover Art:', style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 12),
                      ElevatedButton(
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
                        const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Collaborative Playlist', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Allow other users to edit', style: TextStyle(color: Colors.grey)),
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
                        child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          if (newName.isNotEmpty && newName != playlist.name) {
                            await ref.read(localPlaylistsProvider.notifier).renamePlaylist(playlist.name, newName);
                          }
                          await ref.read(localPlaylistsProvider.notifier).updatePlaylistDetails(
                                newName.isNotEmpty ? newName : playlist.name,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Download', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${song.song_name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${song.song_name}"')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting song: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          child: Column(
            children: [
              if (_songs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(currentSongNotifierProvider.notifier).updatePlaylist(_songs, 0);
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.black),
                    label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
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
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          song.thumbnail_url,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.music_note, size: 48),
                        ),
                      ),
                      title: Text(
                        song.song_name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
    if (playlist.customCoverPath != null && playlist.customCoverPath!.isNotEmpty) {
      final file = File(playlist.customCoverPath!);
      if (file.existsSync()) {
        return Image.file(file, width: size, height: size, fit: BoxFit.cover);
      }
    }

    // Grid collage generation from the first 4 songs
    if (playlist.songs.length >= 4) {
      return SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: playlist.songs.take(4).map((song) {
            return Image.network(
              song.thumbnail_url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10),
            );
          }).toList(),
        ),
      );
    }

    if (playlist.songs.isNotEmpty) {
      return Image.network(
        playlist.songs.first.thumbnail_url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: Colors.white10, child: const Icon(Icons.music_note, color: Colors.white70)),
      );
    }

    return Container(
      width: size,
      height: size,
      color: Colors.white.withOpacity(0.05),
      child: const Icon(Icons.playlist_play, color: Colors.white70, size: 28),
    );
  }
}
