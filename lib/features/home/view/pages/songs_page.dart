import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/current_user_notifier.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/widgets/skeleton_shimmer.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key});

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  String _selectedFilter = 'All';

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _showUserAccountDialog(BuildContext context) {
    final currentUser = ref.read(currentUserNotifierProvider);
    final userName = currentUser?.name ?? 'Guest User';
    final userEmail = currentUser?.email ?? 'guest@echonix.com';
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(
            'YouTube Music Connection',
            style: textTheme.titleLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHighest,
                    child: Icon(Icons.person, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          userEmail,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Your Echonix account is connected to YouTube Music using your personal credentials.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Disconnecting YouTube Music...')),
                );
                await PythonBackend.logout();
                ref.invalidate(isYTMConnectedProvider);
                ref.invalidate(getHomeFeedSectionsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out of YouTube Music successfully.')),
                  );
                }
              },
              child: const Text('Disconnect'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildYTMConnectionBanner(BuildContext context, ColorScheme scheme, TextTheme textTheme) {
    return Card.filled(
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, color: scheme.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Connect YouTube Music',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Synchronize your personal history, favorite artists, customized mixtapes, and private playlists directly into Echonix.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                ref.read(homeTabIndexProvider.notifier).state = 3;
              },
              child: const Text('Setup Connection'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recentlyPlayedSongs = ref.watch(homeLocalRepositoryProvider).loadSongs();
    final ytmConnected = ref.watch(isYTMConnectedProvider).value ?? false;
    final dockHeight = ref.watch(dockHeightProvider);
    ref.watch(localPlaylistsProvider);

    final gridItems = recentlyPlayedSongs.take(6).toList();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final filters = ['All', 'Quick picks', 'Trending', 'Recent'];

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
          child: RefreshIndicator(
            onRefresh: () => ref.read(getHomeFeedSectionsProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top header with Greeting and YT Music account / connection icon
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getGreeting(),
                          style: textTheme.headlineMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (ytmConnected)
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.surfaceContainerHigh,
                              foregroundColor: scheme.primary,
                            ),
                            onPressed: () => _showUserAccountDialog(context),
                            icon: const Icon(Icons.account_circle, size: 24),
                          )
                        else
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: scheme.outlineVariant),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () {
                              ref.read(homeTabIndexProvider.notifier).state = 3;
                            },
                            icon: Icon(Icons.link_off_rounded, color: scheme.onSurfaceVariant, size: 16),
                            label: Text('Connect', style: textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
                          ),
                      ],
                    ),
                  ),
                ),

                // Connection banner if not connected
                if (!ytmConnected)
                  SliverToBoxAdapter(
                    child: _buildYTMConnectionBanner(context, scheme, textTheme),
                  ),

                // Horizontally scrollable FilterChip row
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final f = filters[idx];
                        final isSelected = _selectedFilter == f;
                        return FilterChip(
                          label: Text(f),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              _selectedFilter = f;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Quick picks 2-column grid of compact Card.filled tiles (no shrinkWrap)
                if ((_selectedFilter == 'All' || _selectedFilter == 'Recent' || _selectedFilter == 'Quick picks') &&
                    gridItems.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        'Quick picks',
                        style: textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = gridItems[index];
                          return Card.filled(
                            color: scheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                ref.read(currentSongNotifierProvider.notifier).updateSong(song);
                              },
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
                                      color: scheme.surfaceContainerHighest,
                                      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                                      child: Text(
                                        song.song_name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleSmall?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: gridItems.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                // Stale feed offline notice
                if (ref.watch(isHomeFeedStaleProvider))
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, color: scheme.tertiary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Showing cached feed (offline or refresh failed)',
                              style: textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Home sections
                ref.watch(getHomeFeedSectionsProvider).when(
                      data: (sections) {
                        if (sections.isEmpty) {
                          return SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'No items available.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }

                        final filteredSections = sections.where((sec) {
                          if (_selectedFilter == 'All') return true;
                          final title = (sec['title'] as String? ?? '').toLowerCase();
                          if (_selectedFilter == 'Quick picks') return sec['isSongSection'] == true;
                          if (_selectedFilter == 'Trending') return title.contains('trend') || title.contains('hit') || title.contains('hot');
                          if (_selectedFilter == 'Recent') return title.contains('recent') || title.contains('listen');
                          return true;
                        }).toList();

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final section = filteredSections[index];
                              final title = section['title'] as String? ?? 'Section';
                              final contents = section['contents'] as List? ?? [];
                              final isSongSection = section['isSongSection'] as bool? ?? false;
                              if (contents.isEmpty) return const SizedBox.shrink();

                              if (isSongSection) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                      child: Text(
                                        title,
                                        style: textTheme.titleLarge?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 180,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.only(left: 16.0),
                                        itemCount: contents.length,
                                        itemBuilder: (context, cIndex) {
                                          final item = contents[cIndex];
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
                                                    SongModel.fromBackend(Map<String, dynamic>.from(c), hexCode: 'B388FF'),
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
                                            child: Container(
                                              width: 148,
                                              margin: const EdgeInsets.only(right: 14.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(16),
                                                    child: CachedNetworkImage(
                                                      imageUrl: thumb,
                                                      width: 148,
                                                      height: 120,
                                                      memCacheWidth: 296,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (context, url, error) => Container(
                                                        width: 148,
                                                        height: 120,
                                                        color: scheme.surfaceContainerHigh,
                                                        child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    itemTitle,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: textTheme.titleSmall?.copyWith(
                                                      color: scheme.onSurface,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    itemArtist,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: textTheme.bodySmall?.copyWith(
                                                      color: scheme.onSurfaceVariant,
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
                              }

                              // Album / Playlist carousel with 148 dp cards (artwork radius 16, 1-line title, 1-line artist)
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    child: Text(
                                      title,
                                      style: textTheme.titleLarge?.copyWith(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 220,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.only(left: 16.0),
                                      itemCount: contents.length,
                                      itemBuilder: (context, cIndex) {
                                        final item = contents[cIndex];
                                        final itemTitle = item['title'] as String? ?? '';
                                        final thumb = item['thumbnail'] as String? ?? '';
                                        final id = item['id'] as String? ?? '';
                                        final type = item['type'] as String? ?? 'album';

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
                                          child: Container(
                                            width: 148,
                                            margin: const EdgeInsets.only(right: 14.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(16),
                                                  child: CachedNetworkImage(
                                                    imageUrl: thumb,
                                                    width: 148,
                                                    height: 148,
                                                    memCacheWidth: 296,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (context, url, error) => Container(
                                                      width: 148,
                                                      height: 148,
                                                      color: scheme.surfaceContainerHigh,
                                                      child: Icon(Icons.album_rounded, color: scheme.onSurfaceVariant, size: 40),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  itemTitle,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: textTheme.titleSmall?.copyWith(
                                                    color: scheme.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  type.toUpperCase(),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: textTheme.bodySmall?.copyWith(
                                                    color: scheme.onSurfaceVariant,
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
                            childCount: filteredSections.length,
                          ),
                        );
                      },
                      error: (error, st) => SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not load feed.',
                                style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: () => ref.invalidate(getHomeFeedSectionsProvider),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      loading: () => const SliverToBoxAdapter(child: HomeFeedSkeleton()),
                    ),

                // Responsive bottom spacing derived from dockHeightProvider + 16
                SliverToBoxAdapter(
                  child: SizedBox(height: dockHeight + 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
