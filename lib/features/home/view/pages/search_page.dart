import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/utils.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/widgets/loader.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/view/pages/playlist_details_page.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/core/widgets/add_to_playlist_dialog.dart';
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
  bool _trendingFailed = false;

  // Speech recognition state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _speechError = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      setState(() {}); // Rebuild to show/hide history on focus change
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
    // Try loading from cached box first
    final cachedSongs = localRepo.box.get('trending_songs');
    final cachedAlbums = localRepo.box.get('trending_albums');
    if (cachedSongs != null && cachedAlbums != null) {
      setState(() {
        _trendingSongs = List<Map<String, dynamic>>.from(cachedSongs.map((e) => Map<String, dynamic>.from(e)));
        _trendingAlbums = List<Map<String, dynamic>>.from(cachedAlbums.map((e) => Map<String, dynamic>.from(e)));
      });
    }

    // Refresh in background/periodically
    setState(() {
      _loadingTrending = _trendingSongs.isEmpty;
      _trendingFailed = false;
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
          _trendingFailed = false;
        });
        localRepo.box.put('trending_songs', _trendingSongs);
        localRepo.box.put('trending_albums', _trendingAlbums);
      } else {
        if (mounted && _trendingSongs.isEmpty) {
          setState(() => _trendingFailed = true);
        }
      }
    } catch (_) {
      if (mounted && _trendingSongs.isEmpty) {
        setState(() => _trendingFailed = true);
      }
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

    // Add query to local search history
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

  void _downloadSong(SongModel song) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Starting download for "${song.song_name}"...')),
    );
    try {
      final res = await PythonBackend.downloadSong(
        song.id,
        song.song_name,
        song.artist,
        song.thumbnail_url,
      );
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded "${song.song_name}" successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${res['error'] ?? 'Unknown error'}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: $e')),
      );
    }
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
          child: Padding(
            padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Search Input Field with Voice option
                TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  onSubmitted: _performSearch,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'What do you want to listen to?',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasActiveQuery)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
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
                            color: _isListening ? Colors.redAccent : Colors.grey,
                          ),
                          onPressed: _isListening ? _stopListening : _startListening,
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.purpleAccent, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Speech listening overlay
                if (_isListening)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(CupertinoIcons.mic_fill, size: 72, color: Colors.purpleAccent),
                          ),
                          const SizedBox(height: 24),
                          const Text('Listening...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(_searchController.text, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else if (_speechError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(_speechError, style: const TextStyle(color: Colors.redAccent)),
                  ),

                if (!_isListening)
                  Expanded(
                    child: _isLoading
                        ? const Loader()
                        : _errorMessage.isNotEmpty
                            ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.grey)))
                            : hasActiveQuery
                                ? _buildSuggestionsOrResults()
                                : _buildHistoryAndTrending(history),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsOrResults() {
    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final song = _searchResults[index];
          return ListTile(
            onTap: () {
              ref.read(currentSongNotifierProvider.notifier).updatePlaylist(_searchResults, index);
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: getHighQualityThumbnail(song.thumbnail_url),
                width: 48,
                height: 48,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    const Icon(Icons.music_note),
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
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              color: const Color(0xFF1E1E1E),
              onSelected: (value) {
                if (value == 'download') {
                  _downloadSong(song);
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
          );
        },
      );
    }

    // Show suggestions as we type
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        // Text completion queries
        if (_textSuggestions.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Suggestions', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ..._textSuggestions.map((query) => ListTile(
                leading: const Icon(Icons.search, color: Colors.white30),
                title: Text(query, style: const TextStyle(color: Colors.white)),
                onTap: () => _performSearch(query),
              )),
        ],

        // Failsafe "search for..."
        ListTile(
          leading: const Icon(Icons.search, color: Colors.purpleAccent),
          title: Text('Search for "${_searchController.text}"', style: const TextStyle(color: Colors.purpleAccent)),
          onTap: () => _performSearch(_searchController.text),
        ),
      ],
    );
  }

  Widget _buildHistoryAndTrending(List<String> history) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        // Recent Searches
        if (history.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent searches',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              TextButton(
                onPressed: () {
                  ref.read(homeLocalRepositoryProvider).clearSearchHistory();
                  setState(() {});
                },
                child: const Text('Clear all', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          ...history.take(5).map((query) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: Colors.grey),
                title: Text(query, style: const TextStyle(color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                  onPressed: () {
                    ref.read(homeLocalRepositoryProvider).removeSearchFromHistory(query);
                    setState(() {});
                  },
                ),
                onTap: () => _performSearch(query),
              )),
          const SizedBox(height: 24),
        ],

        // Trending Searches
        if (_loadingTrending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(child: CupertinoActivityIndicator(color: Colors.purpleAccent)),
          )
        else if (_trendingFailed && _trendingSongs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Couldn't load trending.",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                TextButton(
                  onPressed: _loadTrendingSearches,
                  child: const Text('Retry', style: TextStyle(color: Colors.purpleAccent)),
                ),
              ],
            ),
          )
        else ...[
          if (_trendingSongs.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Trending Songs',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ..._trendingSongs.map((song) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    // Play trending song
                    final model = SongModel.fromBackend(Map<String, dynamic>.from(song), hexCode: 'B388FF');
                    ref.read(currentSongNotifierProvider.notifier).updateSong(model);
                  },
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: getHighQualityThumbnail(song['thumbnail'] ?? ''),
                      width: 44,
                      height: 44,
                      memCacheWidth: 88,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.music_note),
                    ),
                  ),
                  title: Text(
                    song['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    song['artist'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )),
            const SizedBox(height: 24),
          ],

          if (_trendingAlbums.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Trending Albums & Playlists',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
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
                      width: 110,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: getHighQualityThumbnail(album['thumbnail'] ?? ''),
                              width: 110,
                              height: 110,
                              memCacheWidth: 220,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.album, size: 110, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            album['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            album['artist'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ],
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, SongModel song) {
    showAddToPlaylistDialog(context, ref, song);
  }
}
