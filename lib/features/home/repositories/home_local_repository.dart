import 'package:client/features/home/models/song_model.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_local_repository.g.dart';

@riverpod
HomeLocalRepository homeLocalRepository(HomeLocalRepositoryRef ref) {
  return HomeLocalRepository();
}

class HomeLocalRepository {
  final Box box = Hive.box();

  static const _specialKeys = {
    'search_history',
    'recently_played',
    'listening_history',
    'most_played',
    'saved_albums',
    'saved_artists',
    'home_feed_cache',
    'palette_cache',
    'lyrics_cache',
    'liked_ids',
    'sync_outbox',
  };

  void uploadLocalSong(SongModel song) {
    box.put(song.id, song.toJson());
  }

  List<SongModel> loadSongs() {
    List<SongModel> songs = [];
    for (final key in box.keys) {
      if (_specialKeys.contains(key)) continue;
      try {
        songs.add(SongModel.fromJson(box.get(key)));
      } catch (_) {}
    }
    return songs;
  }

  // 1. Search History
  List<String> getSearchHistory() {
    final List? history = box.get('search_history');
    if (history == null) return [];
    return List<String>.from(history);
  }

  void addSearchToHistory(String query) {
    if (query.trim().isEmpty) return;
    final history = getSearchHistory();
    history.removeWhere((q) => q.toLowerCase() == query.trim().toLowerCase());
    history.insert(0, query.trim());
    if (history.length > 50) {
      history.removeLast();
    }
    box.put('search_history', history);
  }

  void removeSearchFromHistory(String query) {
    final history = getSearchHistory();
    history.removeWhere((q) => q.toLowerCase() == query.trim().toLowerCase());
    box.put('search_history', history);
  }

  void clearSearchHistory() {
    box.delete('search_history');
  }

  // 2. Recently Played
  List<SongModel> getRecentlyPlayed() {
    final List? list = box.get('recently_played');
    if (list == null) return [];
    return list.map((s) => SongModel.fromMap(Map<String, dynamic>.from(s))).toList();
  }

  void recordRecentlyPlayed(SongModel song) {
    final list = getRecentlyPlayed();
    list.removeWhere((s) => s.id == song.id);
    list.insert(0, song);
    if (list.length > 50) {
      list.removeLast();
    }
    box.put('recently_played', list.map((s) => s.toMap()).toList());
  }

  // 3. Listening History
  List<Map<String, dynamic>> getListeningHistory() {
    final List? list = box.get('listening_history');
    if (list == null) return [];
    return list.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void recordPlaybackHistory(SongModel song) {
    final list = getListeningHistory();
    list.insert(0, {
      'song': song.toMap(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (list.length > 200) {
      list.removeLast();
    }
    box.put('listening_history', list);
  }

  void clearListeningHistory() {
    box.delete('listening_history');
  }

  // 4. Most Played
  Map<String, int> getPlayCounts() {
    final Map? counts = box.get('most_played');
    if (counts == null) return {};
    return Map<String, int>.from(counts);
  }

  void incrementPlayCount(String songId) {
    final counts = getPlayCounts();
    counts[songId] = (counts[songId] ?? 0) + 1;
    box.put('most_played', counts);
  }

  List<SongModel> getMostPlayedSongs(List<SongModel> allKnownSongs) {
    final counts = getPlayCounts();
    final sortedSongs = List<SongModel>.from(allKnownSongs);
    sortedSongs.removeWhere((s) => (counts[s.id] ?? 0) == 0);
    sortedSongs.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    return sortedSongs;
  }

  // 5. Saved Albums
  List<Map<String, dynamic>> getSavedAlbums() {
    final List? list = box.get('saved_albums');
    if (list == null) return [];
    return list.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void saveAlbum(Map<String, dynamic> album) {
    final list = getSavedAlbums();
    if (list.any((a) => a['id'] == album['id'])) return;
    list.insert(0, album);
    box.put('saved_albums', list);
  }

  void removeAlbum(String albumId) {
    final list = getSavedAlbums();
    list.removeWhere((a) => a['id'] == albumId);
    box.put('saved_albums', list);
  }

  bool isAlbumSaved(String albumId) {
    final list = getSavedAlbums();
    return list.any((a) => a['id'] == albumId);
  }

  // 6. Saved Artists
  List<Map<String, dynamic>> getSavedArtists() {
    final List? list = box.get('saved_artists');
    if (list == null) return [];
    return list.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void saveArtist(Map<String, dynamic> artist) {
    final list = getSavedArtists();
    if (list.any((a) => a['id'] == artist['id'])) return;
    list.insert(0, artist);
    box.put('saved_artists', list);
  }

  void removeArtist(String artistId) {
    final list = getSavedArtists();
    list.removeWhere((a) => a['id'] == artistId);
    box.put('saved_artists', list);
  }

  bool isArtistSaved(String artistId) {
    final list = getSavedArtists();
    return list.any((a) => a['id'] == artistId);
  }

  // 7. Home Feed Cache
  Map<String, dynamic>? getCachedHomeFeed() {
    final data = box.get('home_feed_cache');
    if (data == null) return null;
    try {
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    return null;
  }

  void setCachedHomeFeed(List<Map<String, dynamic>> sections) {
    box.put('home_feed_cache', {
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'sections': sections,
    });
  }
}

final recentlyPlayedProvider = Provider<List<SongModel>>((ref) {
  return ref.watch(homeLocalRepositoryProvider).getRecentlyPlayed();
});

final listeningHistoryProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(homeLocalRepositoryProvider).getListeningHistory();
});

final savedAlbumsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(homeLocalRepositoryProvider).getSavedAlbums();
});

final savedArtistsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(homeLocalRepositoryProvider).getSavedArtists();
});
