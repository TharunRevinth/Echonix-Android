import 'package:client/core/recommendation/listening_signals.dart';
import 'package:client/core/recommendation/ranking.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SongModel makeSong({
    required String id,
    required String title,
    required String artist,
  }) {
    return SongModel(
      id: id,
      song_name: title,
      artist: artist,
      thumbnail_url: 'https://example.com/thumb.jpg',
      song_url: 'https://example.com/song.m4a',
      hex_code: 'B388FF',
    );
  }

  final now = DateTime(2026, 10, 15, 12, 0);

  group('Next-song Candidate Ranking Tests', () {
    test('1. Candidate artist completed >= 2 times in last 14d gets +3 and ranks higher', () {
      final songA = makeSong(id: 'song_a', title: 'Song Alpha', artist: 'Artist A');
      final songB = makeSong(id: 'song_b', title: 'Song Beta', artist: 'Artist B');

      final signals = [
        ListeningSignal(
          videoId: 'old_1',
          artist: 'Artist B',
          startedAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          playedMs: 180000,
          durationMs: 180000,
          completed: true,
          skippedEarly: false,
        ),
        ListeningSignal(
          videoId: 'old_2',
          artist: 'Artist B',
          startedAt: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
          playedMs: 200000,
          durationMs: 200000,
          completed: true,
          skippedEarly: false,
        ),
      ];

      // Even though songA is at position 0 (bonus +0.5), songB artist has 2 completions (+3.0)
      final ranked = rank([songA, songB], signals, now);
      expect(ranked.first.id, equals('song_b'));
      expect(ranked.last.id, equals('song_a'));
    });

    test('2. Liked candidate gets +2 and ranks above non-liked candidate', () {
      final songA = makeSong(id: 'song_a', title: 'Track One', artist: 'Solo');
      final songB = makeSong(id: 'song_b', title: 'Track Two', artist: 'Solo');

      final ranked = rank([songA, songB], [], now, likedIds: {'song_b'});
      expect(ranked.first.id, equals('song_b'));
    });

    test('3. Skipped early candidate receives -4 penalty', () {
      final songA = makeSong(id: 'song_a', title: 'First Choice', artist: 'Various');
      final songB = makeSong(id: 'song_b', title: 'Second Choice', artist: 'Various');

      final signals = [
        ListeningSignal(
          videoId: 'song_a',
          artist: 'Various',
          startedAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          playedMs: 5000,
          durationMs: 210000,
          completed: false,
          skippedEarly: true,
        ),
      ];

      // songA was skipped early, so it suffers -4.0 penalty
      final ranked = rank([songA, songB], signals, now);
      expect(ranked.first.id, equals('song_b'));
      expect(ranked.last.id, equals('song_a'));
    });

    test('4. Same Unicode script as current track receives +1 boost', () {
      final currentTrack = makeSong(id: 'curr', title: 'கனவே கனவே', artist: 'Anirudh');
      final songLatin = makeSong(id: 'song_en', title: 'Dream On', artist: 'Aerosmith');
      final songTamil = makeSong(id: 'song_ta', title: 'விழி மூடி', artist: 'Karthik');

      // songLatin starts at position 0 (position bonus 0.5)
      // songTamil is at position 1 (position bonus 0.0) but has +1.0 script match
      final ranked = rank([songLatin, songTamil], [], now, currentTrack: currentTrack);
      expect(ranked.first.id, equals('song_ta'));
    });
  });
}
