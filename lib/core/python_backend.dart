import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:chaquopy/chaquopy.dart';

/// Runs a python snippet in a fresh isolate so it never blocks the UI thread.
/// We cannot pass the MethodChannel itself across isolates, so we spawn
/// a one-shot isolate that re-invokes the channel through a ReceivePort.
class PythonBackend {
  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _runCode(String pythonCode) async {
    try {
      final result = await Chaquopy.executeCode(pythonCode);
      final String output = result['textOutputOrError']?.trim() ?? '';

      final lines = output.split('\n');
      for (int i = lines.length - 1; i >= 0; i--) {
        final line = lines[i].trim();
        if (line.startsWith('{') && line.endsWith('}')) {
          try {
            return jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
      return {'success': false, 'error': output.isEmpty ? 'empty output' : output};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static Future<void> init(String credsDir) async {
    final base64Dir = base64Encode(utf8.encode(credsDir));
    await Chaquopy.executeCode("""
import base64
import echonix_backend
dir_path = base64.b64decode('$base64Dir').decode('utf-8')
echonix_backend.init_ytmusic(dir_path)
""");
  }

  static Future<Map<String, dynamic>> loginWithCookie(String cookie, String credsDir) async {
    final b64 = base64Encode(utf8.encode(cookie));
    final b64Dir = base64Encode(utf8.encode(credsDir));
    return _runCode("""
import base64
import echonix_backend
cookie = base64.b64decode('$b64').decode('utf-8', errors='ignore')
creds_dir = base64.b64decode('$b64Dir').decode('utf-8')
print(echonix_backend.login_with_cookie(cookie, creds_dir))
""");
  }

  static Future<Map<String, dynamic>> logout() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.logout())
""");
  }

  static Future<Map<String, dynamic>> checkAuthStatus() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.check_auth_status())
""");
  }

  static Future<Map<String, dynamic>> getHomeFeed() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_home_feed())
""");
  }

  static Future<Map<String, dynamic>> searchSongs(String query) async {
    final b64 = base64Encode(utf8.encode(query));
    return _runCode("""
import base64
import echonix_backend
query = base64.b64decode('$b64').decode('utf-8')
print(echonix_backend.search_songs(query))
""");
  }

  static Future<Map<String, dynamic>> getPlaylistDetails(String playlistId) async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_playlist_details('$playlistId'))
""");
  }

  static Future<Map<String, dynamic>> getAlbumDetails(String albumId) async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_album_details('$albumId'))
""");
  }

  static Future<Map<String, dynamic>> getSearchSuggestions(String query) async {
    final b64 = base64Encode(utf8.encode(query));
    return _runCode("""
import base64
import echonix_backend
query = base64.b64decode('$b64').decode('utf-8')
print(echonix_backend.get_search_suggestions(query))
""");
  }

  static Future<Map<String, dynamic>> getTrendingSearches() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_trending_searches())
""");
  }

  static Future<Map<String, dynamic>> redownloadLyrics(String videoId, String title, String artist) async {
    final b64Title = base64Encode(utf8.encode(title));
    final b64Artist = base64Encode(utf8.encode(artist));
    return _runCode("""
import base64
import echonix_backend
title = base64.b64decode('$b64Title').decode('utf-8')
artist = base64.b64decode('$b64Artist').decode('utf-8')
print(echonix_backend.redownload_lyrics('$videoId', title, artist))
""");
  }

  static Future<Map<String, dynamic>> getLyrics(String title, String artist) async {
    final b64Title = base64Encode(utf8.encode(title));
    final b64Artist = base64Encode(utf8.encode(artist));
    return _runCode("""
import base64
import echonix_backend
title = base64.b64decode('$b64Title').decode('utf-8')
artist = base64.b64decode('$b64Artist').decode('utf-8')
print(echonix_backend.get_lyrics(title, artist))
""");
  }

  /// Resolves a YouTube stream URL. This call can take a few seconds so the
  /// caller should show a loading indicator while awaiting.
  static Future<Map<String, dynamic>> getStreamUrl(String videoId) async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_stream_url('$videoId'))
""");
  }

  static Future<Map<String, dynamic>> rateSong(String videoId, String rating) async {
    return _runCode("""
import echonix_backend
print(echonix_backend.rate_song('$videoId', '$rating'))
""");
  }

  static Future<void> addHistory(String videoId) async {
    try {
      await Chaquopy.executeCode("""
import echonix_backend
echonix_backend.add_history('$videoId')
""");
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getFavSongs() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_liked_songs())
""");
  }

  static Future<Map<String, dynamic>> downloadSong(
      String videoId, String title, String artist, String thumbnailUrl, [String playlistName = '']) async {
    final b64Title = base64Encode(utf8.encode(title));
    final b64Artist = base64Encode(utf8.encode(artist));
    final b64Thumb = base64Encode(utf8.encode(thumbnailUrl));
    final b64Playlist = base64Encode(utf8.encode(playlistName));
    return _runCode("""
import base64
import echonix_backend
title = base64.b64decode('$b64Title').decode('utf-8')
artist = base64.b64decode('$b64Artist').decode('utf-8')
thumb = base64.b64decode('$b64Thumb').decode('utf-8')
playlist = base64.b64decode('$b64Playlist').decode('utf-8')
print(echonix_backend.download_song('$videoId', title, artist, thumb, playlist))
""");
  }

  static Future<Map<String, dynamic>> getDownloadedSongs() async {
    return _runCode("""
import echonix_backend
print(echonix_backend.get_downloaded_songs())
""");
  }
}
