import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/current_user_notifier.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SongsPage extends ConsumerWidget {
  const SongsPage({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  List<List<dynamic>> _chunkList(List<dynamic> list, int chunkSize) {
    List<List<dynamic>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }

  void _showUserAccountDialog(BuildContext context, WidgetRef ref) {
    final currentUser = ref.read(currentUserNotifierProvider);
    final userName = currentUser?.name ?? 'Guest User';
    final userEmail = currentUser?.email ?? 'guest@echonix.com';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: const Text(
            'YouTube Music Connection',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          userEmail,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Your Echonix account is connected to YouTube Music using your personal credentials.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Disconnecting YouTube Music...'),
                  ),
                );
                await PythonBackend.logout();
                ref.invalidate(isYTMConnectedProvider);
                ref.invalidate(getHomeFeedSectionsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logged out of YouTube Music successfully.'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Logout / Disconnect'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildYTMConnectionBanner(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D0D0D),
            const Color(0xFF1E1E1E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Connect YouTube Music',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Synchronize your personal history, favorite artists, customized mixtapes, and private playlists directly into Echonix.',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.read(homeTabIndexProvider.notifier).state = 3; // Switch to settings
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Setup Connection',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChip(BuildContext context, WidgetRef ref, String label, Color bgColor, Color textColor, Color borderColor) {
    return GestureDetector(
      onTap: () {
        ref.read(searchQueryProvider.notifier).state = label;
        ref.read(homeTabIndexProvider.notifier).state = 1; // switch to search tab
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayedSongs = ref.watch(homeViewModelProvider.notifier).getRecentlyPlayedSongs();
    final ytmConnected = ref.watch(isYTMConnectedProvider).value ?? false;
    final currentUser = ref.watch(currentUserNotifierProvider);
    ref.watch(localPlaylistsProvider); // Warm up local playlists so they are pre-loaded

    // Use a maximum of 6 recently played items for the Spotify grid
    final gridItems = recentlyPlayedSongs.take(6).toList();

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
          child: RefreshIndicator(
            onRefresh: () => ref.read(getHomeFeedSectionsProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
            // Top Bar with ECHONIX Logo and YTMusic connected status / connect button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ECHONIX',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (ytmConnected)
                      GestureDetector(
                        onTap: () => _showUserAccountDialog(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'YT Music',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.white54,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          ref.read(homeTabIndexProvider.notifier).state = 3; // Switch to Settings tab
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.link_off_rounded,
                                color: Colors.white70,
                                size: 14,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Connect YT',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Greeting text
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  _getGreeting(),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),

            // Setup connection CTA banner if not connected
            if (!ytmConnected)
              SliverToBoxAdapter(
                child: _buildYTMConnectionBanner(context, ref),
              ),

            // Mood chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMoodChip(
                        context,
                        ref,
                        'Trending',
                        Colors.orange.withOpacity(0.1),
                        Colors.orangeAccent,
                        Colors.orange.withOpacity(0.2),
                      ),
                      _buildMoodChip(
                        context,
                        ref,
                        'Chill',
                        Colors.blue.withOpacity(0.1),
                        Colors.blueAccent,
                        Colors.blue.withOpacity(0.2),
                      ),
                      _buildMoodChip(
                        context,
                        ref,
                        'Party',
                        Colors.pink.withOpacity(0.1),
                        Colors.pinkAccent,
                        Colors.pink.withOpacity(0.2),
                      ),
                      _buildMoodChip(
                        context,
                        ref,
                        'Romance',
                        Colors.red.withOpacity(0.1),
                        Colors.redAccent,
                        Colors.red.withOpacity(0.2),
                      ),
                      _buildMoodChip(
                        context,
                        ref,
                        'Workout',
                        Colors.green.withOpacity(0.1),
                        Colors.greenAccent,
                        Colors.green.withOpacity(0.2),
                      ),
                      _buildMoodChip(
                        context,
                        ref,
                        'Night',
                        Colors.purple.withOpacity(0.1),
                        Colors.purpleAccent,
                        Colors.purple.withOpacity(0.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Spotify-style 2-column grid of recently played
            if (gridItems.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recently played',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: gridItems.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 3.0,
                        ),
                        itemBuilder: (context, index) {
                          final song = gridItems[index];
                          return GestureDetector(
                            onTap: () {
                              ref.read(currentSongNotifierProvider.notifier).updateSong(song);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Row(
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: song.thumbnail_url,
                                    width: 56,
                                    height: 56,
                                    memCacheWidth: 112,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => Container(
                                      width: 56,
                                      height: 56,
                                      color: const Color(0xFF282828),
                                      child: const Icon(Icons.music_note, color: Colors.white54),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      song.song_name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

            if (ref.watch(isHomeFeedStaleProvider))
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded, color: Colors.amber, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Showing cached feed (offline or refresh failed)',
                        style: TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

            // Home sections (either YT Music connected sections or Fallback trending hits)
            ref.watch(getHomeFeedSectionsProvider).when(
                  data: (sections) {
                    if (sections.isEmpty) {
                      return const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No items available.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final section = sections[index];
                          final title = section['title'] as String? ?? 'Section';
                          final contents = section['contents'] as List? ?? [];
                          final isSongSection = section['isSongSection'] as bool? ?? false;
                          if (contents.isEmpty) return const SizedBox();

                          // If it is a song section, render in a grid-like horizontal list (like YT Music Quick picks)
                          if (isSongSection) {
                            final chunks = _chunkList(contents, 4);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 260, // Fixed height to fit 4 compact list items
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: chunks.length,
                                    padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                                    itemBuilder: (context, chunkIdx) {
                                      final chunk = chunks[chunkIdx];
                                      return Container(
                                        width: MediaQuery.of(context).size.width * 0.85,
                                        margin: const EdgeInsets.only(right: 16.0),
                                        child: Column(
                                          children: chunk.map((item) {
                                            final itemTitle = item['title'] as String? ?? '';
                                            final itemArtist = item['artists'] as String? ?? '';
                                            final thumb = item['thumbnail'] as String? ?? '';
                                            final id = item['id'] as String? ?? '';

                                            return GestureDetector(
                                              onTap: () {
                                                final List<SongModel> sectionSongs = [];
                                                int clickedIndex = 0;
                                                for (final c in contents) {
                                                  if (c['type'] == 'song') {
                                                    if (c['id'] == id) {
                                                      clickedIndex = sectionSongs.length;
                                                    }
                                                    sectionSongs.add(
                                                      SongModel(
                                                        id: c['id'] ?? '',
                                                        song_name: c['title'] ?? '',
                                                        artist: c['artists'] ?? '',
                                                        thumbnail_url: c['thumbnail'] ?? '',
                                                        song_url: 'https://www.youtube.com/watch?v=${c['id']}',
                                                        hex_code: 'B388FF',
                                                      ),
                                                    );
                                                  }
                                                }
                                                if (sectionSongs.isNotEmpty) {
                                                  ref.read(currentSongNotifierProvider.notifier).updatePlaylist(
                                                        sectionSongs,
                                                        clickedIndex,
                                                      );
                                                }
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                                child: Row(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: CachedNetworkImage(
                                                        imageUrl: thumb,
                                                        width: 50,
                                                        height: 50,
                                                        memCacheWidth: 100,
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context, url, error) => Container(
                                                          width: 50,
                                                          height: 50,
                                                          color: const Color(0xFF282828),
                                                          child: const Icon(Icons.music_note, color: Colors.white54),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            itemTitle,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            itemArtist,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              color: Colors.grey,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const Icon(Icons.play_arrow_rounded, color: Colors.white54),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          }

                          // If it is an Album / Playlist section, render as a horizontal scroll of cards
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 195,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: contents.length,
                                  padding: const EdgeInsets.only(left: 16.0),
                                  itemBuilder: (context, cIndex) {
                                    final item = contents[cIndex];
                                    final itemTitle = item['title'] as String? ?? '';
                                    final thumb = item['thumbnail'] as String? ?? '';
                                    final id = item['id'] as String? ?? '';
                                    final type = item['type'] as String? ?? 'song';

                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => PlaylistDetailsPage(
                                              id: id,
                                              title: itemTitle,
                                              thumbnailUrl: thumb,
                                              isAlbum: type == 'album',
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: CachedNetworkImage(
                                                imageUrl: thumb,
                                                width: 130,
                                                height: 130,
                                                memCacheWidth: 260,
                                                fit: BoxFit.cover,
                                                errorWidget: (context, url, error) => const Icon(
                                                  Icons.music_note,
                                                  size: 130,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              width: 130,
                                              child: Text(
                                                itemTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 130,
                                              child: Text(
                                                type.toUpperCase(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                        childCount: sections.length,
                      ),
                    );
                  },
                  error: (error, st) => SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load feed.', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => ref.invalidate(getHomeFeedSectionsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  loading: () => const SliverFillRemaining(child: Loader()),
                ),
            // Bottom space so items aren't hidden by bottom bar & music slab
            const SliverToBoxAdapter(
              child: SizedBox(height: 110),
            ),
          ],
        ),
      ),
    ),
    ),
  );
}


}
