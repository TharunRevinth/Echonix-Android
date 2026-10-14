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
  Future<Either<AppFailure, List<SongModel>>> searchSongs(String query) async {
    try {
      final res = await PythonBackend.searchSongs(query);
      if (res['success'] != true) {
        return Left(AppFailure(res['error'] ?? 'Failed to search songs'));
      }
      final List songsData = res['songs'] ?? [];
      final songs = songsData
          .map((s) => SongModel.fromBackend(Map<String, dynamic>.from(s as Map), hexCode: 'B388FF'))
          .toList();
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
      final songs = songsData
          .map((s) => SongModel.fromBackend(Map<String, dynamic>.from(s as Map), hexCode: 'B388FF'))
          .toList();
      return Right(songs);
    } catch (e) {
      return Left(AppFailure(e.toString()));
    }
  }
}
