import 'dart:io';
import 'dart:ui';

import 'package:client/core/providers/current_user_notifier.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/models/fav_song_model.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/repositories/home_repository.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/providers/bootstrap_provider.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
part 'home_viewmodel.g.dart';

final isHomeFeedStaleProvider = StateProvider<bool>((ref) => false);

@riverpod
Future<bool> isYTMConnected(IsYTMConnectedRef ref) async {
  await ref.watch(bootstrapProvider.future);
  final status = await PythonBackend.checkAuthStatus();
  return status['authenticated'] ?? false;
}

@riverpod
Future<List<SongModel>> getFavSongs(GetFavSongsRef ref) async {
  final token =
      ref.watch(currentUserNotifierProvider.select((user) => user!.token));
  final res = await ref.watch(homeRepositoryProvider).getFavSongs(
        token: token,
      );

  return switch (res) {
    Left(value: final l) => throw l.message,
    Right(value: final r) => r,
  };
}

@riverpod
class GetHomeFeedSections extends _$GetHomeFeedSections {
  @override
  FutureOr<List<Map<String, dynamic>>> build() async {
    final localRepo = ref.watch(homeLocalRepositoryProvider);
    final cached = localRepo.getCachedHomeFeed();
    final cachedSections = cached != null && cached['sections'] != null
        ? (cached['sections'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final savedAt = cached != null ? (cached['savedAt'] as num?)?.toInt() ?? 0 : 0;
    final isOlderThan15Min = DateTime.now().millisecondsSinceEpoch - savedAt > 15 * 60 * 1000;

    if (cachedSections.isNotEmpty) {
      if (isOlderThan15Min) {
        Future.microtask(() => refresh());
      }
      return cachedSections;
    }

    return _fetchFromNetwork();
  }

  Future<void> refresh() async {
    try {
      final fresh = await _fetchFromNetwork();
      state = AsyncData(fresh);
      ref.read(isHomeFeedStaleProvider.notifier).state = false;
    } catch (e) {
      if (state.hasValue && state.value!.isNotEmpty) {
        ref.read(isHomeFeedStaleProvider.notifier).state = true;
      } else {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFromNetwork() async {
    await ref.watch(bootstrapProvider.future);
    final res = await PythonBackend.getHomeFeed();
    if (res['success'] == true) {
      final List sections = res['sections'] ?? [];
      if (sections.isNotEmpty) {
        final list = List<Map<String, dynamic>>.from(
          sections.map((e) => Map<String, dynamic>.from(e as Map)),
        );
        ref.read(homeLocalRepositoryProvider).setCachedHomeFeed(list);
        return list;
      }
    }

    // Fallback: search for trending hits
    final fallbackRes = await PythonBackend.searchSongs("trending hits");
    if (fallbackRes['success'] == true) {
      final List songsData = fallbackRes['songs'] ?? [];
      final List parsedContents = songsData.map((s) => {
        'title': s['title'] ?? '',
        'thumbnail': s['thumbnail'] ?? '',
        'artists': s['artist'] ?? '',
        'id': s['id'] ?? '',
        'type': 'song',
      }).toList();
      final list = [
        {
          'title': 'Trending Hits',
          'isSongSection': true,
          'contents': parsedContents,
        }
      ];
      ref.read(homeLocalRepositoryProvider).setCachedHomeFeed(list);
      return list;
    }

    throw Exception(res['error'] ?? 'Failed to load home feed');
  }
}

@riverpod
class HomeViewModel extends _$HomeViewModel {
  HomeRepository get _homeRepository => ref.read(homeRepositoryProvider);
  HomeLocalRepository get _homeLocalRepository => ref.read(homeLocalRepositoryProvider);

  @override
  AsyncValue? build() {
    return null;
  }

  Future<void> uploadSong({
    required File selectedAudio,
    required File selectedThumbnail,
    required String songName,
    required String artist,
    required Color selectedColor,
  }) async {
    state = const AsyncValue.loading();
    final res = await _homeRepository.uploadSong(
      selectedAudio: selectedAudio,
      selectedThumbnail: selectedThumbnail,
      songName: songName,
      artist: artist,
      hexCode: rgbToHex(selectedColor),
      token: ref.read(currentUserNotifierProvider)!.token,
    );

    final val = switch (res) {
      Left(value: final l) => state =
          AsyncValue.error(l.message, StackTrace.current),
      Right(value: final r) => state = AsyncValue.data(r),
    };
    print(val);
  }

  List<SongModel> getRecentlyPlayedSongs() {
    return _homeLocalRepository.loadSongs();
  }

  Future<void> favSong({required String songId}) async {
    state = const AsyncValue.loading();
    final res = await _homeRepository.favSong(
      songId: songId,
      token: ref.read(currentUserNotifierProvider)!.token,
    );

    final val = switch (res) {
      Left(value: final l) => state =
          AsyncValue.error(l.message, StackTrace.current),
      Right(value: final r) => _favSongSuccess(r, songId),
    };
    print(val);
  }

  AsyncValue _favSongSuccess(bool isFavorited, String songId) {
    final userNotifier = ref.read(currentUserNotifierProvider.notifier);
    if (isFavorited) {
      userNotifier.addUser(
        ref.read(currentUserNotifierProvider)!.copyWith(
          favorites: [
            ...ref.read(currentUserNotifierProvider)!.favorites,
            FavSongModel(
              id: '',
              song_id: songId,
              user_id: '',
            ),
          ],
        ),
      );
    } else {
      userNotifier.addUser(
        ref.read(currentUserNotifierProvider)!.copyWith(
              favorites: ref
                  .read(currentUserNotifierProvider)!
                  .favorites
                  .where(
                    (fav) => fav.song_id != songId,
                  )
                  .toList(),
            ),
      );
    }
    ref.invalidate(getFavSongsProvider);
    return state = AsyncValue.data(isFavorited);
  }
}
