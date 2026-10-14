import 'dart:async';
import 'dart:convert';
import 'package:chaquopy/chaquopy.dart';

class PythonBackend {
  // ---------------------------------------------------------------------------
  // Internal helper
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _call(
    String fn,
    Map<String, dynamic> args, {
    String lane = 'background',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final raw = await Chaquopy.invoke(fn, args, lane: lane, timeout: timeout);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': true, 'data': decoded};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static Future<void> init(String credsDir) async {
    await Chaquopy.invoke(
      'init_ytmusic',
      {'creds_dir': credsDir},
      lane: 'priority',
    );
  }

  static Future<Map<String, dynamic>> loginWithCookie(String cookie, String credsDir) async {
    return _call(
      'login_with_cookie',
      {'cookie_str_or_curl': cookie, 'creds_dir': credsDir},
      lane: 'priority',
    );
  }

  static Future<Map<String, dynamic>> logout() async {
    return _call('logout', {});
  }

  static Future<Map<String, dynamic>> checkAuthStatus() async {
    return _call('check_auth_status', {}, lane: 'priority');
  }

  static Future<Map<String, dynamic>> getHomeFeed() async {
    return _call('get_home_feed', {});
  }

  static Future<Map<String, dynamic>> searchSongs(String query) async {
    return _call('search_songs', {'query': query});
  }

  static Future<Map<String, dynamic>> getPlaylistDetails(String playlistId) async {
    return _call('get_playlist_details', {'playlist_id': playlistId});
  }

  static Future<Map<String, dynamic>> getAlbumDetails(String albumId) async {
    return _call('get_album_details', {'album_id': albumId});
  }

  static Future<Map<String, dynamic>> getSearchSuggestions(String query) async {
    return _call('get_search_suggestions', {'query': query});
  }

  static Future<Map<String, dynamic>> getTrendingSearches({String? country}) async {
    return _call('get_trending_searches', {'country': country ?? 'ZZ'});
  }

  static Future<Map<String, dynamic>> redownloadLyrics(String videoId, String title, String artist) async {
    return _call('redownload_lyrics', {
      'video_id': videoId,
      'title': title,
      'artist': artist,
    });
  }

  static Future<Map<String, dynamic>> getLyrics(
    String title,
    String artist, {
    int? durationSeconds,
  }) async {
    final Map<String, dynamic> args = {
      'title': title,
      'artist': artist,
    };
    if (durationSeconds != null) {
      args['duration_seconds'] = durationSeconds;
    }
    return _call('get_lyrics', args);
  }

  static Future<Map<String, dynamic>> getStreamUrl(String videoId) async {
    return _call('get_stream_url', {'video_id': videoId}, lane: 'priority');
  }

  static Future<Map<String, dynamic>> resolveStream(String videoId, {String lane = 'priority'}) async {
    return _call('resolve_stream', {'video_id': videoId}, lane: lane);
  }

  static Future<Map<String, dynamic>> resolveStreamDownload(String videoId, {String lane = 'priority'}) async {
    return _call('resolve_stream_download', {'video_id': videoId}, lane: lane);
  }

  static Future<Map<String, dynamic>> rateSong(String videoId, String rating) async {
    return _call('rate_song', {'video_id': videoId, 'rating': rating}, lane: 'priority');
  }

  static Future<void> addHistory(String videoId) async {
    try {
      await _call('add_history', {'video_id': videoId});
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getFavSongs() async {
    return _call('get_liked_songs', {});
  }

  static Future<Map<String, dynamic>> downloadSong(
    String videoId,
    String title,
    String artist,
    String thumbnailUrl, [
    String playlistName = '',
  ]) async {
    return _call('download_song', {
      'video_id': videoId,
      'title': title,
      'artist': artist,
      'thumbnail_url': thumbnailUrl,
      'playlist_name': playlistName,
    });
  }

  static Future<Map<String, dynamic>> getDownloadedSongs() async {
    return _call('get_downloaded_songs', {});
  }
}
