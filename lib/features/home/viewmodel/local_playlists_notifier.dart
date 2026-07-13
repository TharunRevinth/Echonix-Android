import 'dart:convert';
import 'package:client/features/home/models/song_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomPlaylist {
  final String name;
  final List<SongModel> songs;
  final String description;
  final String? customCoverPath;
  final bool isCollaborative;
  final List<String> collaborators;
  final int version;

  CustomPlaylist({
    required this.name,
    required this.songs,
    this.description = '',
    this.customCoverPath,
    this.isCollaborative = false,
    this.collaborators = const [],
    this.version = 1,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'songs': songs.map((s) => s.toMap()).toList(),
        'description': description,
        'customCoverPath': customCoverPath,
        'isCollaborative': isCollaborative,
        'collaborators': collaborators,
        'version': version,
      };

  factory CustomPlaylist.fromMap(Map<String, dynamic> map) {
    return CustomPlaylist(
      name: map['name'] ?? '',
      songs: List<SongModel>.from(
        (map['songs'] ?? []).map((x) => SongModel.fromMap(x as Map<String, dynamic>)),
      ),
      description: map['description'] ?? '',
      customCoverPath: map['customCoverPath'],
      isCollaborative: map['isCollaborative'] ?? false,
      collaborators: List<String>.from(map['collaborators'] ?? []),
      version: map['version'] ?? 1,
    );
  }

  CustomPlaylist copyWith({
    String? name,
    List<SongModel>? songs,
    String? description,
    String? customCoverPath,
    bool? isCollaborative,
    List<String>? collaborators,
    int? version,
  }) {
    return CustomPlaylist(
      name: name ?? this.name,
      songs: songs ?? this.songs,
      description: description ?? this.description,
      customCoverPath: customCoverPath ?? this.customCoverPath,
      isCollaborative: isCollaborative ?? this.isCollaborative,
      collaborators: collaborators ?? this.collaborators,
      version: version ?? this.version,
    );
  }
}

class LocalPlaylistsNotifier extends StateNotifier<List<CustomPlaylist>> {
  LocalPlaylistsNotifier() : super([]) {
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_playlists');
    if (data != null) {
      try {
        final List decoded = jsonDecode(data);
        state = decoded.map((x) => CustomPlaylist.fromMap(x as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(state.map((p) => p.toMap()).toList());
    await prefs.setString('custom_playlists', data);
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    if (state.any((p) => p.name.toLowerCase() == name.trim().toLowerCase())) return;
    state = [...state, CustomPlaylist(name: name.trim(), songs: [])];
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String name) async {
    state = state.where((p) => p.name != name).toList();
    await _savePlaylists();
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    if (newName.trim().isEmpty) return;
    if (state.any((p) => p.name.toLowerCase() == newName.trim().toLowerCase())) return;
    state = state.map((p) {
      if (p.name == oldName) {
        return p.copyWith(name: newName.trim());
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  Future<void> updatePlaylistDetails(
    String playlistName, {
    String? description,
    String? customCoverPath,
    bool? isCollaborative,
  }) async {
    state = state.map((p) {
      if (p.name == playlistName) {
        return p.copyWith(
          description: description ?? p.description,
          customCoverPath: customCoverPath ?? p.customCoverPath,
          isCollaborative: isCollaborative ?? p.isCollaborative,
          version: p.version + 1,
        );
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  Future<void> reorderSongInPlaylist(String playlistName, int oldIndex, int newIndex) async {
    state = state.map((p) {
      if (p.name == playlistName) {
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
    await _savePlaylists();
  }

  Future<void> addSongToPlaylist(String playlistName, SongModel song) async {
    state = state.map((p) {
      if (p.name == playlistName) {
        if (p.songs.any((s) => s.id == song.id)) return p;
        return p.copyWith(songs: [...p.songs, song]);
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistName, String songId) async {
    state = state.map((p) {
      if (p.name == playlistName) {
        return p.copyWith(songs: p.songs.where((s) => s.id != songId).toList());
      }
      return p;
    }).toList();
    await _savePlaylists();
  }
}

final localPlaylistsProvider = StateNotifierProvider<LocalPlaylistsNotifier, List<CustomPlaylist>>((ref) {
  return LocalPlaylistsNotifier();
});
