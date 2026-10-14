import 'dart:convert';
// ignore_for_file: non_constant_identifier_names

class SongModel {
  final String id;
  final String song_name;
  final String artist;
  final String thumbnail_url;
  final String song_url;
  final String hex_code;
  final int? duration_seconds;
  final String? album;

  SongModel({
    required this.id,
    required this.song_name,
    required this.artist,
    required this.thumbnail_url,
    required this.song_url,
    required this.hex_code,
    this.duration_seconds,
    this.album,
  });

  SongModel copyWith({
    String? id,
    String? song_name,
    String? artist,
    String? thumbnail_url,
    String? song_url,
    String? hex_code,
    int? duration_seconds,
    String? album,
  }) {
    return SongModel(
      id: id ?? this.id,
      song_name: song_name ?? this.song_name,
      artist: artist ?? this.artist,
      thumbnail_url: thumbnail_url ?? this.thumbnail_url,
      song_url: song_url ?? this.song_url,
      hex_code: hex_code ?? this.hex_code,
      duration_seconds: duration_seconds ?? this.duration_seconds,
      album: album ?? this.album,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'song_name': song_name,
      'artist': artist,
      'thumbnail_url': thumbnail_url,
      'song_url': song_url,
      'hex_code': hex_code,
      if (duration_seconds != null) 'duration_seconds': duration_seconds,
      if (album != null) 'album': album,
    };
  }

  factory SongModel.fromMap(Map<String, dynamic> map) {
    return SongModel(
      id: map['id']?.toString() ?? '',
      song_name: map['song_name']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      thumbnail_url: map['thumbnail_url']?.toString() ?? '',
      song_url: map['song_url']?.toString() ?? '',
      hex_code: map['hex_code']?.toString() ?? '',
      duration_seconds: map['duration_seconds'] is num
          ? (map['duration_seconds'] as num).toInt()
          : null,
      album: map['album']?.toString(),
    );
  }

  factory SongModel.fromBackend(Map<String, dynamic> m, {String? hexCode}) {
    final id = (m['videoId'] ?? m['id'] ?? '').toString();
    final title = (m['title'] ?? m['name'] ?? m['song_name'] ?? '').toString();

    String artist = '';
    if (m['artists'] is List) {
      final list = m['artists'] as List;
      artist = list
          .map((a) {
            if (a is Map) return a['name']?.toString() ?? '';
            return a?.toString() ?? '';
          })
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
    } else if (m['artist'] is String) {
      artist = m['artist'] as String;
    } else if (m['artist'] is Map) {
      artist = (m['artist'] as Map)['name']?.toString() ?? '';
    } else if (m['artists'] is String) {
      artist = m['artists'] as String;
    }

    String? album;
    if (m['album'] is Map) {
      final n = (m['album'] as Map)['name']?.toString();
      if (n != null && n.trim().isNotEmpty) album = n.trim();
    } else if (m['album'] is String) {
      final n = (m['album'] as String).trim();
      if (n.isNotEmpty) album = n;
    }

    int? durationSeconds;
    final durSec = m['duration_seconds'];
    if (durSec is num) {
      durationSeconds = durSec.toInt();
    } else if (m['duration'] is String) {
      final durStr = m['duration'] as String;
      final parts = durStr.split(':').map((p) => int.tryParse(p.trim())).toList();
      if (parts.isNotEmpty && !parts.contains(null)) {
        if (parts.length == 1) {
          durationSeconds = parts[0];
        } else if (parts.length == 2) {
          durationSeconds = parts[0]! * 60 + parts[1]!;
        } else if (parts.length == 3) {
          durationSeconds = parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
        }
      }
    }

    String thumbnail = '';
    final rawThumb = m['thumbnails'] ?? m['thumbnail'] ?? m['thumbnail_url'];
    if (rawThumb is List && rawThumb.isNotEmpty) {
      final thumbs = List<Map>.from(rawThumb.whereType<Map>());
      if (thumbs.isNotEmpty) {
        thumbs.sort((a, b) {
          final wA = (a['width'] as num?)?.toInt() ?? 0;
          final wB = (b['width'] as num?)?.toInt() ?? 0;
          return wA.compareTo(wB);
        });
        thumbnail = thumbs.last['url']?.toString() ?? '';
      }
    } else if (rawThumb is String && rawThumb.trim().isNotEmpty) {
      thumbnail = rawThumb.trim();
    }
    if (thumbnail.isEmpty) {
      thumbnail = 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=150';
    }

    String songUrl = (m['song_url'] ?? m['path'] ?? m['youtube_url'] ?? '').toString();
    if (songUrl.isEmpty && id.isNotEmpty) {
      songUrl = 'https://www.youtube.com/watch?v=$id';
    }

    return SongModel(
      id: id,
      song_name: title,
      artist: artist,
      thumbnail_url: thumbnail,
      song_url: songUrl,
      hex_code: hexCode ?? (m['hex_code']?.toString() ?? '000000'),
      duration_seconds: durationSeconds,
      album: album,
    );
  }

  String toJson() => json.encode(toMap());

  factory SongModel.fromJson(String source) =>
      SongModel.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'SongModel(id: $id, song_name: $song_name, artist: $artist, thumbnail_url: $thumbnail_url, song_url: $song_url, hex_code: $hex_code, duration_seconds: $duration_seconds, album: $album)';
  }

  @override
  bool operator ==(covariant SongModel other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.song_name == song_name &&
        other.artist == artist &&
        other.thumbnail_url == thumbnail_url &&
        other.song_url == song_url &&
        other.hex_code == hex_code &&
        other.duration_seconds == duration_seconds &&
        other.album == album;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        song_name.hashCode ^
        artist.hashCode ^
        thumbnail_url.hashCode ^
        song_url.hashCode ^
        hex_code.hashCode ^
        duration_seconds.hashCode ^
        album.hashCode;
  }
}
