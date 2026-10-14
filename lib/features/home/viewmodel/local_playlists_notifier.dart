import 'dart:convert';
import 'dart:math';
import 'package:client/features/home/models/song_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

String generateDeterministicUuid(String input) {
  final rand = Random(input.hashCode);
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

String generateUuidV4() {
  final rand = Random();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

class CustomPlaylist {
  final String id;
  final String? remoteId;
  final String name;
  final List<SongModel> songs;
  final String description;
  final String? customCoverPath;
  final bool isCollaborative;
  final List<String> collaborators;
  final int version;
  final bool syncEnabled;

  CustomPlaylist({
    required this.id,
    this.remoteId,
    required this.name,
    required this.songs,
    this.description = '',
    this.customCoverPath,
    this.isCollaborative = false,
    this.collaborators = const [],
    this.version = 1,
    this.syncEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'remoteId': remoteId,
        'name': name,
        'songs': songs.map((s) => s.toMap()).toList(),
        'description': description,
        'customCoverPath': customCoverPath,
        'isCollaborative': isCollaborative,
        'collaborators': collaborators,
        'version': version,
        'syncEnabled': syncEnabled,
      };

  factory CustomPlaylist.fromMap(Map<String, dynamic> map) {
    final name = map['name'] ?? '';
    final id = map['id'] ?? generateDeterministicUuid(name);
    return CustomPlaylist(
      id: id,
      remoteId: map['remoteId'],
      name: name,
      songs: List<SongModel>.from(
        (map['songs'] ?? []).map((x) => SongModel.fromMap(x as Map<String, dynamic>)),
      ),
      description: map['description'] ?? '',
      customCoverPath: map['customCoverPath'],
      isCollaborative: map['isCollaborative'] ?? false,
      collaborators: List<String>.from(map['collaborators'] ?? []),
      version: map['version'] ?? 1,
      syncEnabled: map['syncEnabled'] ?? true,
    );
  }

  CustomPlaylist copyWith({
    String? id,
    String? remoteId,
    String? name,
    List<SongModel>? songs,
    String? description,
    String? customCoverPath,
    bool? isCollaborative,
    List<String>? collaborators,
    int? version,
    bool? syncEnabled,
  }) {
    return CustomPlaylist(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      description: description ?? this.description,
      customCoverPath: customCoverPath ?? this.customCoverPath,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      collaborators: collaborators ?? this.collaborators,
      version: version ?? this.version,
      syncEnabled: syncEnabled ?? this.syncEnabled,
    );
  }
}

class LocalPlaylistsNotifier extends StateNotifier<List<CustomPlaylist>> {
  LocalPlaylistsNotifier() : super([]) {
    _loadPlaylists();
  }

  void _loadPlaylists() async {
    final box = Hive.box();
    final rawHive = box.get('custom_playlists_v2');

    if (rawHive is List && rawHive.isNotEmpty) {
      try {
        state = rawHive
            .map((x) => CustomPlaylist.fromMap(Map<String, dynamic>.from(x as Map)))
            .toList();
        return;
      } catch (_) {}
    }

    // Migration from SharedPreferences key `custom_playlists`
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_playlists');
    if (data != null && data.isNotEmpty) {
      try {
        final List decoded = jsonDecode(data);
        final migrated = decoded.map((x) {
          final m = Map<String, dynamic>.from(x as Map);
          if (m['id'] == null || (m['id'] as String).isEmpty) {
            m['id'] = generateDeterministicUuid(m['name'] ?? '');
          }
          return CustomPlaylist.fromMap(m);
        }).toList();
        state = migrated;
        box.put('custom_playlists_v2', state.map((p) => p.toMap()).toList());
        return;
      } catch (_) {}
    }

    state = [];
  }

  void _savePlaylists() {
    final box = Hive.box();
    box.put('custom_playlists_v2', state.map((p) => p.toMap()).toList());
  }

  Future<String> createPlaylist(String name, {String? description, String? remoteId}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return '';
    final id = generateUuidV4();
    final playlist = CustomPlaylist(
      id: id,
      remoteId: remoteId,
      name: trimmedName,
      description: description ?? '',
      songs: [],
    );
    state = [...state, playlist];
    _savePlaylists();
    return id;
  }

  Future<void> deletePlaylist(String idOrName) async {
    state = state.where((p) => p.id != idOrName && p.name != idOrName).toList();
    _savePlaylists();
  }

  Future<void> renamePlaylist(String idOrName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    state = state.map((p) {
      if (p.id == idOrName || p.name == idOrName) {
        return p.copyWith(name: trimmed);
      }
      return p;
    }).toList();
    _savePlaylists();
  }

  Future<void> updatePlaylistDetails(
    String idOrName, {
    String? name,
    String? description,
    String? customCoverPath,
    bool? isCollaborative,
    String? remoteId,
    bool? syncEnabled,
  }) async {
    state = state.map((p) {
      if (p.id == idOrName || p.name == idOrName) {
        return p.copyWith(
          name: name ?? p.name,
          description: description ?? p.description,
          customCoverPath: customCoverPath ?? p.customCoverPath,
          isCollaborative: isCollaborative ?? p.isCollaborative,
          remoteId: remoteId ?? p.remoteId,
          syncEnabled: syncEnabled ?? p.syncEnabled,
          version: p.version + 1,
        );
      }
      return p;
    }).toList();
    _savePlaylists();
  }

  Future<void> reorderSongInPlaylist(String idOrName, int oldIndex, int newIndex) async {
    state = state.map((p) {
      if (p.id == idOrName || p.name == idOrName) {
        final songs = List<SongModel>.from(p.songs);
        if (oldIndex < 0 || oldIndex >= songs.length) return p;
        if (newIndex < 0 || newIndex > songs.length) return p;
        final song = songs.removeAt(oldIndex);
        if (newIndex > oldIndex) {
          newIndex--;
        }
        songs.insert(newIndex, song);
        return p.copyWith(songs: songs);
      }
      return p;
    }).toList();
    _savePlaylists();
  }

  Future<void> addSongToPlaylist(String idOrName, SongModel song) async {
    state = state.map((p) {
      if (p.id == idOrName || p.name == idOrName) {
        if (p.songs.any((s) => s.id == song.id)) return p;
        return p.copyWith(songs: [...p.songs, song]);
      }
      return p;
    }).toList();
    _savePlaylists();
  }

  Future<void> removeSongFromPlaylist(String idOrName, String songId) async {
    state = state.map((p) {
      if (p.id == idOrName || p.name == idOrName) {
        return p.copyWith(songs: p.songs.where((s) => s.id != songId).toList());
      }
      return p;
    }).toList();
    _savePlaylists();
  }
}

final localPlaylistsProvider =
    StateNotifierProvider<LocalPlaylistsNotifier, List<CustomPlaylist>>((ref) {
  return LocalPlaylistsNotifier();
});
