import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/sync/sync_service.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';

class LikesNotifier extends StateNotifier<Set<String>> {
  final Ref ref;
  final Box _box;

  LikesNotifier(this.ref)
      : _box = Hive.box(),
        super({}) {
    _loadInitialState();
  }

  void _loadInitialState() {
    final rawIds = _box.get('liked_ids');
    if (rawIds is List) {
      state = Set<String>.from(rawIds.map((e) => e.toString()));
    } else {
      state = {};
    }
  }

  bool isLiked(String id) => state.contains(id);

  Future<void> toggle(SongModel song) async {
    final id = song.id;
    final isCurrentlyLiked = state.contains(id);
    final nextState = Set<String>.from(state);

    final rawMeta = _box.get('liked_songs_metadata');
    final Map<String, dynamic> metadataMap =
        rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : {};

    if (isCurrentlyLiked) {
      nextState.remove(id);
      metadataMap.remove(id);
      state = nextState;
      _box.put('liked_ids', nextState.toList());
      _box.put('liked_songs_metadata', metadataMap);

      // Enqueue INDIFFERENT (un-like)
      ref.read(syncServiceProvider.notifier).enqueue('rate', {'videoId': id, 'rating': 'INDIFFERENT'});
    } else {
      nextState.add(id);
      metadataMap[id] = song.toJson();
      state = nextState;
      _box.put('liked_ids', nextState.toList());
      _box.put('liked_songs_metadata', metadataMap);
      ref.read(homeLocalRepositoryProvider).uploadLocalSong(song);

      // Enqueue LIKE
      ref.read(syncServiceProvider.notifier).enqueue('rate', {'videoId': id, 'rating': 'LIKE'});
    }
  }

  void syncRemoteIds(Set<String> mergedIds, List<SongModel> remoteSongs) {
    state = mergedIds;
    final rawMeta = _box.get('liked_songs_metadata');
    final Map<String, dynamic> metadataMap =
        rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : {};

    for (final song in remoteSongs) {
      if (mergedIds.contains(song.id)) {
        metadataMap[song.id] = song.toJson();
      }
    }
    metadataMap.removeWhere((id, _) => !mergedIds.contains(id));

    _box.put('liked_ids', mergedIds.toList());
    _box.put('liked_songs_metadata', metadataMap);
  }

  void mergeRemoteLikes(List<SongModel> remoteSongs) {
    final nextState = Set<String>.from(state);
    final rawMeta = _box.get('liked_songs_metadata');
    final Map<String, dynamic> metadataMap =
        rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : {};

    for (final song in remoteSongs) {
      nextState.add(song.id);
      if (!metadataMap.containsKey(song.id)) {
        metadataMap[song.id] = song.toJson();
      }
    }

    state = nextState;
    _box.put('liked_ids', nextState.toList());
    _box.put('liked_songs_metadata', metadataMap);
  }
}

final likedSongIdsProvider =
    StateNotifierProvider<LikesNotifier, Set<String>>((ref) {
  return LikesNotifier(ref);
});

final favoriteSongsProvider = FutureProvider<List<SongModel>>((ref) async {
  final likedIds = ref.watch(likedSongIdsProvider);
  final Box box = Hive.box();

  // 1. Show locally liked songs first from Hive
  final rawMeta = box.get('liked_songs_metadata');
  final Map<String, dynamic> metadataMap =
      rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : {};

  final List<SongModel> localSongs = [];
  for (final id in likedIds) {
    if (metadataMap.containsKey(id)) {
      try {
        final songJson = metadataMap[id];
        if (songJson is String) {
          localSongs.add(SongModel.fromJson(songJson));
        } else if (songJson is Map) {
          localSongs.add(SongModel.fromMap(Map<String, dynamic>.from(songJson)));
        }
      } catch (_) {}
    } else {
      final rawSong = box.get(id);
      if (rawSong is String) {
        try {
          localSongs.add(SongModel.fromJson(rawSong));
        } catch (_) {}
      }
    }
  }

  // 2. Fetch remote liked songs in background and merge
  try {
    final res = await PythonBackend.getFavSongs();
    if (res['success'] == true && res['songs'] is List) {
      final List rawSongs = res['songs'] as List;
      final List<SongModel> remoteSongs = [];
      for (final s in rawSongs) {
        if (s is Map) {
          final model = SongModel.fromBackend(Map<String, dynamic>.from(s), hexCode: 'B388FF');
          if (model.id.isNotEmpty) {
            remoteSongs.add(model);
          }
        }
      }

      if (remoteSongs.isNotEmpty) {
        ref.read(likedSongIdsProvider.notifier).mergeRemoteLikes(remoteSongs);

        final Set<String> seenIds = localSongs.map((s) => s.id).toSet();
        final List<SongModel> merged = List.of(localSongs);
        for (final rSong in remoteSongs) {
          if (!seenIds.contains(rSong.id)) {
            merged.add(rSong);
            seenIds.add(rSong.id);
          }
        }
        return merged;
      }
    }
  } catch (_) {}

  return localSongs;
});
