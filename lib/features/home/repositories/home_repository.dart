import 'dart:io';

import 'package:client/core/failure/failure.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/core/python_backend.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'home_repository.g.dart';

@riverpod
HomeRepository homeRepository(HomeRepositoryRef ref) {
  return HomeRepository();
}

class HomeRepository {
  Future<Either<AppFailure, List<SongModel>>> getAllSongs({
    required String token,
  }) async {
    try {
      final res = await PythonBackend.getHomeFeed();
      if (res['success'] != true) {
        final fallbackRes = await PythonBackend.searchSongs("trending hits");
        if (fallbackRes['success'] == true) {
          final List songsData = fallbackRes['songs'] ?? [];
          final songs = songsData.map((s) => SongModel(
            id: s['id'] ?? '',
            song_name: s['title'] ?? '',
            artist: s['artist'] ?? '',
            thumbnail_url: s['thumbnail'] ?? '',
            song_url: 'https://www.youtube.com/watch?v=${s['id']}',
            hex_code: 'B388FF',
          )).toList();
          return Right(songs);
        }
        return Left(AppFailure(res['error'] ?? 'Failed to get home feed'));
      }

      final sections = res['sections'] as List? ?? [];
      final List<SongModel> songs = [];
      for (final sec in sections) {
        if (sec['isSongSection'] == true) {
          final contents = sec['contents'] as List? ?? [];
          for (final item in contents) {
            if (item['type'] == 'song') {
              songs.add(SongModel(
                id: item['id'] ?? '',
                song_name: item['title'] ?? '',
                artist: item['artists'] ?? '',
                thumbnail_url: item['thumbnail'] ?? '',
                song_url: 'https://www.youtube.com/watch?v=${item['id']}',
                hex_code: 'B388FF',
              ));
            }
          }
        }
      }

      if (songs.isEmpty) {
        final fallbackRes = await PythonBackend.searchSongs("trending hits");
        if (fallbackRes['success'] == true) {
          final List songsData = fallbackRes['songs'] ?? [];
          return Right(songsData.map((s) => SongModel(
            id: s['id'] ?? '',
            song_name: s['title'] ?? '',
            artist: s['artist'] ?? '',
            thumbnail_url: s['thumbnail'] ?? '',
            song_url: 'https://www.youtube.com/watch?v=${s['id']}',
            hex_code: 'B388FF',
          )).toList());
        }
      }

      return Right(songs);
    } catch (e) {
      return Left(AppFailure(e.toString()));
    }
  }

  Future<Either<AppFailure, List<SongModel>>> searchSongs(String query) async {
    try {
      final res = await PythonBackend.searchSongs(query);
      if (res['success'] != true) {
        return Left(AppFailure(res['error'] ?? 'Failed to search songs'));
      }
      final List songsData = res['songs'] ?? [];
      final songs = songsData.map((s) => SongModel(
        id: s['id'] ?? '',
        song_name: s['title'] ?? '',
        artist: s['artist'] ?? '',
        thumbnail_url: s['thumbnail'] ?? '',
        song_url: 'https://www.youtube.com/watch?v=${s['id']}',
        hex_code: 'B388FF',
      )).toList();
      return Right(songs);
    } catch (e) {
      return Left(AppFailure(e.toString()));
    }
  }

  Future<Either<AppFailure, String>> uploadSong({
    required File selectedAudio,
    required File selectedThumbnail,
    required String songName,
    required String artist,
    required String hexCode,
    required String token,
  }) async {
    return const Right('Upload not supported locally');
  }

  Future<Either<AppFailure, bool>> favSong({
    required String token,
    required String songId,
  }) async {
    try {
      await PythonBackend.rateSong(songId, 'LIKE');
      return const Right(true);
    } catch (e) {
      return Left(AppFailure(e.toString()));
    }
  }

  Future<Either<AppFailure, List<SongModel>>> getFavSongs({
    required String token,
  }) async {
    try {
      final res = await PythonBackend.getFavSongs();
      if (res['success'] != true) {
        return Left(AppFailure(res['error'] ?? 'Failed to get liked songs'));
      }
      final List songsData = res['songs'] ?? [];
      final songs = songsData.map((s) => SongModel(
        id: s['id'] ?? '',
        song_name: s['title'] ?? '',
        artist: s['artist'] ?? '',
        thumbnail_url: s['thumbnail'] ?? '',
        song_url: 'https://www.youtube.com/watch?v=${s['id']}',
        hex_code: 'B388FF',
      )).toList();
      return Right(songs);
    } catch (e) {
      return Left(AppFailure(e.toString()));
    }
  }
}
