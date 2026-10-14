import 'package:client/features/home/models/song_model.dart';
import 'package:client/core/recommendation/listening_signals.dart';

class RankingWeights {
  static const double artistCompletedTwice14d = 3.0;
  static const double liked = 2.0;
  static const double top5Artist = 1.0;
  static const double skippedEarly7d = -4.0;
  static const double playedWithin2h = -3.0;
  static const double sameScript = 1.0;
  static const double maxPositionBonus = 0.5;
}

enum UnicodeScript {
  latin,
  tamil,
  devanagari,
  telugu,
  kannada,
  malayalam,
  bengali,
  cyrillic,
  arabic,
  cjk,
  other,
}

UnicodeScript getDominantScript(String text) {
  if (text.isEmpty) return UnicodeScript.latin;

  final counts = <UnicodeScript, int>{};

  for (final rune in text.runes) {
    if (rune >= 0x0041 && rune <= 0x024F) {
      counts[UnicodeScript.latin] = (counts[UnicodeScript.latin] ?? 0) + 1;
    } else if (rune >= 0x0B80 && rune <= 0x0BFF) {
      counts[UnicodeScript.tamil] = (counts[UnicodeScript.tamil] ?? 0) + 1;
    } else if (rune >= 0x0900 && rune <= 0x097F) {
      counts[UnicodeScript.devanagari] = (counts[UnicodeScript.devanagari] ?? 0) + 1;
    } else if (rune >= 0x0C00 && rune <= 0x0C7F) {
      counts[UnicodeScript.telugu] = (counts[UnicodeScript.telugu] ?? 0) + 1;
    } else if (rune >= 0x0C80 && rune <= 0x0CFF) {
      counts[UnicodeScript.kannada] = (counts[UnicodeScript.kannada] ?? 0) + 1;
    } else if (rune >= 0x0D00 && rune <= 0x0D7F) {
      counts[UnicodeScript.malayalam] = (counts[UnicodeScript.malayalam] ?? 0) + 1;
    } else if (rune >= 0x0980 && rune <= 0x09FF) {
      counts[UnicodeScript.bengali] = (counts[UnicodeScript.bengali] ?? 0) + 1;
    } else if (rune >= 0x0400 && rune <= 0x04FF) {
      counts[UnicodeScript.cyrillic] = (counts[UnicodeScript.cyrillic] ?? 0) + 1;
    } else if (rune >= 0x0600 && rune <= 0x06FF) {
      counts[UnicodeScript.arabic] = (counts[UnicodeScript.arabic] ?? 0) + 1;
    } else if ((rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3040 && rune <= 0x30FF)) {
      counts[UnicodeScript.cjk] = (counts[UnicodeScript.cjk] ?? 0) + 1;
    }
  }

  if (counts.isEmpty) return UnicodeScript.latin;

  var bestScript = UnicodeScript.latin;
  var maxCount = -1;
  for (final entry in counts.entries) {
    if (entry.value > maxCount) {
      maxCount = entry.value;
      bestScript = entry.key;
    }
  }
  return bestScript;
}

class ScoredCandidate {
  final SongModel song;
  final double score;

  ScoredCandidate(this.song, this.score);
}

List<SongModel> rank(
  List<SongModel> candidates,
  List<ListeningSignal> signals,
  DateTime now, {
  Set<String> likedIds = const {},
  Set<String> top5Artists = const {},
  SongModel? currentTrack,
}) {
  if (candidates.isEmpty) return [];

  final nowMs = now.millisecondsSinceEpoch;
  final twoHoursMs = 2 * 3600 * 1000;
  final sevenDaysMs = 7 * 24 * 3600 * 1000;
  final fourteenDaysMs = 14 * 24 * 3600 * 1000;

  // Pre-calculate artist completion counts in last 14 days
  final artistCompletedCounts = <String, int>{};
  final skippedEarly7dIds = <String>{};
  final played2hIds = <String>{};

  for (final s in signals) {
    final ageMs = nowMs - s.startedAt;
    if (ageMs < 0) continue;

    if (ageMs <= fourteenDaysMs && s.completed && s.artist.isNotEmpty) {
      final aKey = s.artist.toLowerCase();
      artistCompletedCounts[aKey] = (artistCompletedCounts[aKey] ?? 0) + 1;
    }

    if (ageMs <= sevenDaysMs && s.skippedEarly) {
      skippedEarly7dIds.add(s.videoId);
    }

    if (ageMs <= twoHoursMs) {
      played2hIds.add(s.videoId);
    }
  }

  // Pre-calculate top 5 artists if not passed
  final effectiveTop5 = top5Artists.map((a) => a.toLowerCase()).toSet();
  if (effectiveTop5.isEmpty && signals.isNotEmpty) {
    final playCounts = <String, int>{};
    for (final s in signals) {
      if (s.artist.isNotEmpty && s.artist != 'Unknown') {
        final aKey = s.artist.toLowerCase();
        playCounts[aKey] = (playCounts[aKey] ?? 0) + 1;
      }
    }
    final sorted = playCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted.take(5)) {
      effectiveTop5.add(e.key);
    }
  }

  final currentScript = currentTrack != null ? getDominantScript(currentTrack.song_name) : null;
  final n = candidates.length;
  final scoredList = <ScoredCandidate>[];

  for (int i = 0; i < n; i++) {
    final c = candidates[i];
    double score = 0.0;

    // +3 if candidate artist was completed >= 2 times in the last 14 days
    final cArtistKey = c.artist.toLowerCase();
    if ((artistCompletedCounts[cArtistKey] ?? 0) >= 2) {
      score += RankingWeights.artistCompletedTwice14d;
    }

    // +2 if candidate video id was liked
    if (likedIds.contains(c.id)) {
      score += RankingWeights.liked;
    }

    // +1 if artist is among top 5
    if (effectiveTop5.contains(cArtistKey)) {
      score += RankingWeights.top5Artist;
    }

    // -4 if skipped early in the last 7 days
    if (skippedEarly7dIds.contains(c.id)) {
      score += RankingWeights.skippedEarly7d;
    }

    // -3 if played in the last 2 hours
    if (played2hIds.contains(c.id)) {
      score += RankingWeights.playedWithin2h;
    }

    // +1 if same script as current track
    if (currentScript != null) {
      final candScript = getDominantScript(c.song_name);
      if (candScript == currentScript) {
        score += RankingWeights.sameScript;
      }
    }

    // +0.5 linear position bonus (earlier in radio list = higher)
    final double positionBonus = n > 1
        ? RankingWeights.maxPositionBonus * ((n - 1 - i) / (n - 1))
        : RankingWeights.maxPositionBonus;
    score += positionBonus;

    scoredList.add(ScoredCandidate(c, score));
  }

  scoredList.sort((a, b) {
    final cmp = b.score.compareTo(a.score);
    if (cmp != 0) return cmp;
    // Tie breaker: preserve original order
    return candidates.indexOf(a.song).compareTo(candidates.indexOf(b.song));
  });

  return scoredList.map((sc) => sc.song).toList();
}
