import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class ListeningSignal {
  final String videoId;
  final String artist;
  final int startedAt;
  final int playedMs;
  final int durationMs;
  final bool completed;
  final bool skippedEarly;

  ListeningSignal({
    required this.videoId,
    required this.artist,
    required this.startedAt,
    required this.playedMs,
    required this.durationMs,
    required this.completed,
    required this.skippedEarly,
  });

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'artist': artist,
        'startedAt': startedAt,
        'playedMs': playedMs,
        'durationMs': durationMs,
        'completed': completed,
        'skippedEarly': skippedEarly,
      };

  factory ListeningSignal.fromMap(Map<String, dynamic> map) {
    return ListeningSignal(
      videoId: map['videoId']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      startedAt: (map['startedAt'] as num?)?.toInt() ?? 0,
      playedMs: (map['playedMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      completed: map['completed'] == true,
      skippedEarly: map['skippedEarly'] == true,
    );
  }
}

class ListeningSignalsRepository {
  static const String key = 'signals';
  static const int maxEvents = 2000;

  static Box get _box => Hive.box();

  static List<ListeningSignal> loadSignals() {
    try {
      final raw = _box.get(key);
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => ListeningSignal.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (e) {
      debugPrint('[Echonix][signals] loadSignals error: $e');
    }
    return [];
  }

  static void recordSignal(ListeningSignal signal) {
    try {
      final list = loadSignals();
      list.add(signal);
      if (list.length > maxEvents) {
        list.removeRange(0, list.length - maxEvents);
      }
      _box.put(key, list.map((e) => e.toMap()).toList());
    } catch (e) {
      debugPrint('[Echonix][signals] recordSignal error: $e');
    }
  }
}
