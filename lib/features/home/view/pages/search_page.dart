import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/utils.dart';
import 'package:client/core/widgets/add_to_playlist_dialog.dart';
import 'package:client/core/widgets/skeleton_shimmer.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/viewmodel/downloads_notifier.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<SongModel> _searchResults = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Suggestions state
  List<String> _textSuggestions = [];
  Timer? _debounceTimer;
  int _searchSuggestionRequestId = 0;

  // Trending state
  List<Map<String, dynamic>> _trendingSongs = [];
  List<Map<String, dynamic>> _trendingAlbums = [];
  bool _loadingTrending = false;

  // Speech recognition state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _speechError = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      setState(() {});
    });
    _loadTrendingSearches();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      _debounceTimer?.cancel();
      setState(() {
        _textSuggestions = [];
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _fetchSuggestions(query);
    });
  }

  void _fetchSuggestions(String query) async {
    final requestId = ++_searchSuggestionRequestId;
    try {
      final res = await PythonBackend.getSearchSuggestions(query);
      if (requestId != _searchSuggestionRequestId) return;
      if (res['success'] == true && mounted) {
        final List queriesList = res['queries'] ?? [];
        setState(() {
          _textSuggestions = List<String>.from(queriesList);
        });
      }
    } catch (_) {}
  }

  void _loadTrendingSearches() async {
    final localRepo = ref.read(homeLocalRepositoryProvider);
    final cachedSongs = localRepo.box.get('trending_songs');
    final cachedAlbums = localRepo.box.get('trending_albums');
    if (cachedSongs != null && cachedAlbums != null) {
      setState(() {
        _trendingSongs = List<Map<String, dynamic>>.from(cachedSongs.map((e) => Map<String, dynamic>.from(e)));
        _trendingAlbums = List<Map<String, dynamic>>.from(cachedAlbums.map((e) => Map<String, dynamic>.from(e)));
      });
    }

    setState(() {
      _loadingTrending = _trendingSongs.isEmpty;
    });

    try {
      final country = PlatformDispatcher.instance.locale.countryCode ?? 'ZZ';
      final res = await PythonBackend.getTrendingSearches(country: country);
      if (res['success'] == true && mounted) {
        final List songsList = res['songs'] ?? [];
        final List albumsList = res['albums'] ?? [];
        setState(() {
          _trendingSongs = List<Map<String, dynamic>>.from(songsList);
          _trendingAlbums = List<Map<String, dynamic>>.from(albumsList);
        });
        localRepo.box.put('trending_songs', _trendingSongs);
        localRepo.box.put('trending_albums', _trendingAlbums);
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _loadingTrending = false);
      }
    }
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    _searchController.text = query;

    ref.read(homeLocalRepositoryProvider).addSearchToHistory(query);

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _textSuggestions = [];
    });

    try {
      final res = await PythonBackend.searchSongs(query);
      if (res['success'] == true) {
        final List songsList = res['songs'] ?? [];
        setState(() {
          _searchResults = songsList
              .map((s) => SongModel.fromBackend(Map<String, dynamic>.from(s as Map), hexCode: 'B388FF'))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['error'] ?? 'Search failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Search error: $e';
        _isLoading = false;
      });
    }
  }

  void _startListening() async {
    setState(() {
      _speechError = '';
      _isListening = false;
    });

    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' && _isListening) {
            setState(() => _isListening = false);
          }
        },
        onError: (errorNotification) {
          setState(() {
            _isListening = false;
            _speechError = errorNotification.errorMsg;
          });
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) {
            setState(() {
              _searchController.text = result.recognizedWords;
            });
            if (result.finalResult) {
              setState(() => _isListening = false);
              _performSearch(result.recognizedWords);
            }
          },
        );
      } else {
        setState(() => _speechError = 'Speech recognition not available on this device');
      }
    } catch (e) {
      setState(() => _speechError = 'Voice search error: $e');
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _downloadSong(SongModel song) {
    ref.read(downloadsProvider.notifier).startDownloading(song);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download queued: "${song.song_name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (next.isNotEmpty) {
        _searchController.text = next;
        _performSearch(next);
        ref.read(searchQueryProvider.notifier).state = '';
      }
    });

    final history = ref.watch(homeLocalRepositoryProvider).getSearchHistory();
    final hasActiveQuery = _searchController.text.trim().isNotEmpty;
    final dockHeight = ref.watch(dockHeightProvider);
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
          child: CustomScrollView(
            slivers: [
              // Screen title & M3 SearchBar pinned at top
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0, left: 16.0, right: 16.0, bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search',
                        style: textTheme.headlineMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SearchBar(
                        controller: _searchController,
                        focusNode: _focusNode,
                        hintText: 'What do you want to listen to?',
                        leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
                        trailing: [
                          if (hasActiveQuery)
                            IconButton(
                              icon: Icon(Icons.clear, color: scheme.onSurfaceVariant),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                });
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                              color: _isListening ? scheme.error : scheme.onSurfaceVariant,
                            ),
                            onPressed: _isListening ? _stopListening : _startListening,
                          ),
                        ],
                        onSubmitted: _performSearch,
                      ),
                    ],
                  ),
                ),
              ),

              // Voice listening overlay
              if (_isListening)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(CupertinoIcons.mic_fill, size: 64, color: scheme.primary),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Listening...',
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchController.text,
                          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_speechError.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      _speechError,
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ),

              if (!_isListening) ...[
                if (_isLoading)
                  const SliverToBoxAdapter(child: SearchTrendingSkeleton())
                else if (_errorMessage.isNotEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _errorMessage,
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else if (_searchResults.isNotEmpty) ...[
                  // Results as ListTiles with 52 dp artwork, DownloadButton and overflow menu
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _searchResults[index];
                        return ListTile(
                          onTap: () {
                            ref.read(currentSongNotifierProvider.notifier).updatePlaylist(_searchResults, index);
                          },
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                              width: 52,
                              height: 52,
                              memCacheWidth: 104,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                width: 52,
                                height: 52,
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
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
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
                                    _downloadSong(song);
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
                        );
                      },
                      childCount: _searchResults.length,
                    ),
                  ),
                ] else if (hasActiveQuery) ...[
                  // Suggestions as ListTiles
                  if (_textSuggestions.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final query = _textSuggestions[index];
                          return ListTile(
                            leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
                            title: Text(query, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                            onTap: () => _performSearch(query),
                          );
                        },
                        childCount: _textSuggestions.length,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: ListTile(
                      leading: Icon(Icons.search, color: scheme.primary),
                      title: Text(
                        'Search for "${_searchController.text}"',
                        style: textTheme.titleMedium?.copyWith(color: scheme.primary),
                      ),
                      onTap: () => _performSearch(_searchController.text),
                    ),
                  ),
                ] else ...[
                  // Recent searches as InputChips with delete
                  if (history.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent searches',
                              style: textTheme.titleMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                ref.read(homeLocalRepositoryProvider).clearSearchHistory();
                                setState(() {});
                              },
                              child: Text('Clear all', style: textTheme.labelLarge?.copyWith(color: scheme.primary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: history.take(8).map((query) {
                            return InputChip(
                              avatar: Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
                              label: Text(query),
                              onPressed: () => _performSearch(query),
                              onDeleted: () {
                                ref.read(homeLocalRepositoryProvider).removeSearchFromHistory(query);
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],

                  // Trending Searches: 2-column grid of cards (no shrinkWrap)
                  if (_loadingTrending)
                    const SliverToBoxAdapter(child: SearchTrendingSkeleton())
                  else if (_trendingSongs.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          'Trending Songs',
                          style: textTheme.titleMedium?.copyWith(
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
                            final song = _trendingSongs[index];
                            return Card.filled(
                              color: scheme.surfaceContainerHigh,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  final model = SongModel.fromBackend(Map<String, dynamic>.from(song), hexCode: 'B388FF');
                                  ref.read(currentSongNotifierProvider.notifier).updateSong(model);
                                },
                                child: Row(
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: getHighQualityThumbnail(song['thumbnail'] ?? ''),
                                      width: 48,
                                      height: 48,
                                      memCacheWidth: 96,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) => Container(
                                        width: 48,
                                        height: 48,
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            song['title'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.titleSmall?.copyWith(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            song['artist'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _trendingSongs.length,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],

                  // Trending Albums & Playlists
                  if (_trendingAlbums.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          'Trending Albums & Playlists',
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 170,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(left: 16.0),
                          itemCount: _trendingAlbums.length,
                          itemBuilder: (context, index) {
                            final album = _trendingAlbums[index];
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
                              child: Container(
                                width: 116,
                                margin: const EdgeInsets.only(right: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: CachedNetworkImage(
                                        imageUrl: getHighQualityThumbnail(album['thumbnail'] ?? ''),
                                        width: 116,
                                        height: 116,
                                        memCacheWidth: 232,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) => Container(
                                          width: 116,
                                          height: 116,
                                          color: scheme.surfaceContainerHigh,
                                          child: Icon(Icons.album, size: 40, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      album['title'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleSmall?.copyWith(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      album['artist'] ?? '',
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
                    ),
                  ],
                ],
              ],

              // Responsive bottom spacing derived from dockHeightProvider + 16
              SliverToBoxAdapter(
                child: SizedBox(height: dockHeight + 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
