import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/sync/sync_service.dart';
import 'package:client/core/recommendation/listening_signals.dart';
import 'package:client/core/recommendation/ranking.dart';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
part 'current_song_notifier.g.dart';

final shuffleProvider = StateProvider<bool>((ref) => false);
final repeatModeProvider = StateProvider<LoopMode>((ref) => LoopMode.off);
final isPlayerLoadingProvider = StateProvider<bool>((ref) => false);
final queueVersionProvider = StateProvider<int>((ref) => 0);

class AutoplayNotifier extends StateNotifier<bool> {
  AutoplayNotifier() : super(true) {
    _load();
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('autoplay_enabled') ?? true;
  }

  void toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoplay_enabled', state);
  }

  void setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoplay_enabled', enabled);
  }
}

final autoplayEnabledProvider = StateNotifierProvider<AutoplayNotifier, bool>((ref) {
  return AutoplayNotifier();
});

class _StreamCacheEntry {
  final String url;
  final String ext;
  final Map<String, String> headers;
  final DateTime expiresAt;
  final bool isLocal;

  _StreamCacheEntry({
    required this.url,
    required this.ext,
    required this.headers,
    required this.expiresAt,
    required this.isLocal,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class LocalRedirectServer {
  HttpServer? _server;
  int get port => _server?.port ?? 8080;
  final String serverToken = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1000000)}';

  final Map<String, _StreamCacheEntry> _cache = {};
  final HttpClient _httpClient = HttpClient()..autoUncompress = false;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen((HttpRequest request) async {
        try {
          await _handleRequest(request);
        } catch (_) {
          // Seek/skip cancellations or socket closures must not throw to zone
        }
      }, onError: (_) {});
    } catch (e, st) {
      debugPrint("LocalRedirectServer Bind Error: $e\n$st");
    }
  }

  void prefetch(String videoId) {
    if (videoId.isEmpty) return;
    final cached = _cache[videoId];
    if (cached != null && !cached.isExpired) return;

    PythonBackend.resolveStream(videoId, lane: 'background').then((res) {
      if (res['success'] == true) {
        final url = res['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final ext = res['ext'] as String? ?? 'm4a';
          final rawHeaders = res['headers'];
          final headers = <String, String>{};
          if (rawHeaders is Map) {
            rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
          }
          final expiresEpoch = (res['expires_at'] as num?)?.toInt() ??
              (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800);
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresEpoch * 1000);
          final isLocal = res['is_local'] == true || url.startsWith('/');
          _cache[videoId] = _StreamCacheEntry(
            url: url,
            ext: ext,
            headers: headers,
            expiresAt: expiresAt,
            isLocal: isLocal,
          );
        }
      }
    }).catchError((_) {});
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final token = request.uri.queryParameters['t'];
    if (token != serverToken) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final videoId = request.uri.queryParameters['id'];
    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    _StreamCacheEntry? entry = _cache[videoId];
    if (entry != null && entry.isExpired) {
      _cache.remove(videoId);
      entry = null;
    }

    final sw = Stopwatch()..start();

    if (entry == null) {
      final res = await PythonBackend.resolveStream(videoId, lane: 'priority');
      if (res['success'] == true && res['url'] != null) {
        final url = res['url'] as String;
        final ext = res['ext'] as String? ?? 'm4a';
        final rawHeaders = res['headers'];
        final headers = <String, String>{};
        if (rawHeaders is Map) {
          rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
        }
        final expiresEpoch = (res['expires_at'] as num?)?.toInt() ??
            (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800);
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresEpoch * 1000);
        final isLocal = res['is_local'] == true || url.startsWith('/');
        entry = _StreamCacheEntry(
          url: url,
          ext: ext,
          headers: headers,
          expiresAt: expiresAt,
          isLocal: isLocal,
        );
        _cache[videoId] = entry;
        debugPrint('[Echonix][stream] resolve id=$videoId mode=direct ms=${sw.elapsedMilliseconds}');
      }
    }

    if (entry == null) {
      entry = await _fallbackDownload(videoId, sw);
    }

    if (entry == null) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    if (entry.isLocal || entry.url.startsWith('/')) {
      await _serveLocalFile(request, File(entry.url));
      return;
    }

    bool proxySuccess = await _proxyRemoteStream(request, videoId, entry, sw);
    if (!proxySuccess) {
      final fallbackEntry = await _fallbackDownload(videoId, sw);
      if (fallbackEntry != null && fallbackEntry.isLocal) {
        await _serveLocalFile(request, File(fallbackEntry.url));
      } else {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    }
  }

  Future<_StreamCacheEntry?> _fallbackDownload(String videoId, Stopwatch sw) async {
    final dlRes = await PythonBackend.resolveStreamDownload(videoId, lane: 'priority');
    if (dlRes['success'] == true && dlRes['url'] != null) {
      final url = dlRes['url'] as String;
      final ext = dlRes['ext'] as String? ?? 'm4a';
      final entry = _StreamCacheEntry(
        url: url,
        ext: ext,
        headers: {},
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        isLocal: true,
      );
      _cache[videoId] = entry;
      debugPrint('[Echonix][stream] resolve id=$videoId mode=fallback ms=${sw.elapsedMilliseconds}');
      return entry;
    }
    return null;
  }

  Future<bool> _proxyRemoteStream(
    HttpRequest request,
    String videoId,
    _StreamCacheEntry entry,
    Stopwatch sw,
  ) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final upstreamUri = Uri.parse(entry.url);
        final upstreamReq = await _httpClient.getUrl(upstreamUri);

        entry.headers.forEach((k, v) {
          if (k.toLowerCase() != 'host') {
            upstreamReq.headers.set(k, v);
          }
        });

        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        if (rangeHeader != null) {
          upstreamReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
        }

        final upstreamResp = await upstreamReq.close();

        if (upstreamResp.statusCode == HttpStatus.forbidden ||
            upstreamResp.statusCode == HttpStatus.gone ||
            upstreamResp.statusCode >= 400) {
          upstreamResp.drain().catchError((_) {});
          _cache.remove(videoId);
          if (attempt == 0) {
            final reRes = await PythonBackend.resolveStream(videoId, lane: 'priority');
            if (reRes['success'] == true && reRes['url'] != null) {
              final newUrl = reRes['url'] as String;
              final ext = reRes['ext'] as String? ?? 'm4a';
              final rawHeaders = reRes['headers'];
              final headers = <String, String>{};
              if (rawHeaders is Map) {
                rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
              }
              final expiresEpoch = (reRes['expires_at'] as num?)?.toInt() ??
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800);
              final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresEpoch * 1000);
              entry = _StreamCacheEntry(
                url: newUrl,
                ext: ext,
                headers: headers,
                expiresAt: expiresAt,
                isLocal: false,
              );
              _cache[videoId] = entry;
              continue;
            }
          }
          return false;
        }

        request.response.statusCode = upstreamResp.statusCode;
        upstreamResp.headers.forEach((name, values) {
          final lower = name.toLowerCase();
          if (lower == 'content-type' ||
              lower == 'content-length' ||
              lower == 'content-range' ||
              lower == 'accept-ranges') {
            for (final v in values) {
              request.response.headers.add(name, v);
            }
          }
        });

        await upstreamResp.pipe(request.response);
        return true;
      } catch (e) {
        if (e is SocketException || e is HttpException) {
          return true;
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _serveLocalFile(HttpRequest request, File file) async {
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final length = await file.length();
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final ext = file.path.endsWith('.mp3') ? 'mpeg' : 'mp4';
    request.response.headers.contentType = ContentType('audio', ext);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (length - 1)
          : (length - 1);
      final clampedEnd = end.clamp(start, length - 1);
      final chunkSize = clampedEnd - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$clampedEnd/$length');
      request.response.headers.contentLength = chunkSize;
      await file.openRead(start, clampedEnd + 1).pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentLength = length;
      await file.openRead().pipe(request.response);
    }
  }

  void stop() {
    _server?.close();
    _server = null;
    _cache.clear();
  }
}


@Riverpod(keepAlive: true)
class CurrentSongNotifier extends _$CurrentSongNotifier {
  HomeLocalRepository get _homeLocalRepository => ref.read(homeLocalRepositoryProvider);
  AudioPlayer? audioPlayer;
  AndroidEqualizer? _equalizer;
  bool isPlaying = false;
  List<SongModel> playlist = [];
  int currentSongIndex = -1;
  int _playRequestId = 0;
  bool _isServerStarted = false;
  bool _hasCountedForCurrentSong = false;
  bool _needsEqReapply = false;
  List<SongModel>? _unshuffledPlaylist;
  SongModel? _activeSignalTrack;
  int _activeSignalStartedAt = 0;
  int _maxPositionMs = 0;

  void _recordListeningSignal({bool completed = false}) {
    if (_activeSignalTrack == null) return;
    final track = _activeSignalTrack!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final durationMs = audioPlayer?.duration?.inMilliseconds ?? ((track.duration_seconds ?? 0) * 1000);
    final playedMs = _maxPositionMs;

    final isCompleted = completed || (durationMs > 0 && playedMs >= (durationMs * 0.95).toInt());

    int thresholdMs = 30000;
    if (durationMs > 0) {
      final thirtyPercent = (durationMs * 0.3).toInt();
      if (thirtyPercent < thresholdMs) {
        thresholdMs = thirtyPercent;
      }
    }
    final skippedEarly = !isCompleted && (playedMs < thresholdMs);

    ListeningSignalsRepository.recordSignal(ListeningSignal(
      videoId: track.id,
      artist: track.artist,
      startedAt: _activeSignalStartedAt > 0 ? _activeSignalStartedAt : now,
      playedMs: playedMs,
      durationMs: durationMs,
      completed: isCompleted,
      skippedEarly: skippedEarly,
    ));

    _activeSignalTrack = null;
    _maxPositionMs = 0;
  }

  void _startListeningSignal(SongModel song) {
    _recordListeningSignal(completed: false);
    _activeSignalTrack = song;
    _activeSignalStartedAt = DateTime.now().millisecondsSinceEpoch;
    _maxPositionMs = 0;
  }

  bool _isFetchingAutoplay = false;
  String? _lastAutoplayTrackId;

  Future<void> checkAutoplay() async {
    if (_isFetchingAutoplay || state == null) return;
    final autoplayEnabled = ref.read(autoplayEnabledProvider);
    if (!autoplayEnabled) return;

    final repeatMode = ref.read(repeatModeProvider);
    if (repeatMode != LoopMode.off) return;

    final remaining = playlist.length - 1 - currentSongIndex;
    if (remaining > 2) return;

    final currentTrack = state!;
    if (_lastAutoplayTrackId == currentTrack.id) return;

    _isFetchingAutoplay = true;
    _lastAutoplayTrackId = currentTrack.id;

    try {
      final res = await PythonBackend.getUpNext(currentTrack.id, limit: 25);
      if (res['success'] == true && res['tracks'] is List) {
        final List rawTracks = res['tracks'] as List;
        final candidates = rawTracks
            .whereType<Map>()
            .map((t) => SongModel.fromBackend(Map<String, dynamic>.from(t), hexCode: 'B388FF'))
            .where((s) => s.id.isNotEmpty)
            .toList();

        final signals = ListeningSignalsRepository.loadSignals();
        final now = DateTime.now();
        final likedIds = ref.read(likedSongIdsProvider);

        // Drop tracks already in the queue or played in the last 2 hours
        final queueIds = playlist.map((s) => s.id).toSet();
        final twoHoursAgoMs = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
        final playedLast2hIds = signals
            .where((s) => s.startedAt >= twoHoursAgoMs)
            .map((s) => s.videoId)
            .toSet();

        final filteredCandidates = candidates.where((c) {
          return !queueIds.contains(c.id) && !playedLast2hIds.contains(c.id);
        }).toList();

        final ranked = rank(
          filteredCandidates,
          signals,
          now,
          likedIds: likedIds,
          currentTrack: currentTrack,
        );

        final top10 = ranked.take(10).map((s) => s.copyWith(isAutoplay: true)).toList();

        if (top10.isNotEmpty) {
          for (final song in top10) {
            playlist.add(song);
            if (_playlistSource != null) {
              _playlistSource!.add(_buildAudioSource(song));
            }
          }
          ref.read(queueVersionProvider.notifier).state++;
          // Resolve first autoplay track URL in advance (prefetch)
          _redirectServer?.prefetch(top10.first.id);
        }
      }
    } catch (e) {
      debugPrint('[Echonix][autoplay] checkAutoplay error: $e');
    } finally {
      _isFetchingAutoplay = false;
    }
  }

  void removeAutoplayTracks() {
    if (playlist.isEmpty) return;
    for (int i = playlist.length - 1; i > currentSongIndex; i--) {
      if (playlist[i].isAutoplay) {
        removeSongFromQueue(i);
      }
    }
  }

  ConcatenatingAudioSource? _playlistSource;
  LocalRedirectServer? _redirectServer;
  Future<void>? _serverStartFuture;

  @override
  SongModel? build() {
    _initRedirectServer();
    _initAudioPlayer();
    ref.onDispose(() {
      _redirectServer?.stop();
      audioPlayer?.dispose();
    });
    return null;
  }

  void _initRedirectServer() {
    _redirectServer = LocalRedirectServer();
    _serverStartFuture = _redirectServer!.start().then((_) {
      _isServerStarted = true;
    });
  }

  void _initAudioPlayer() {
    if (audioPlayer != null) return;

    if (Platform.isAndroid) {
      try {
        _equalizer = AndroidEqualizer();
        final pipeline = AudioPipeline(
          androidAudioEffects: [_equalizer!],
        );
        audioPlayer = AudioPlayer(audioPipeline: pipeline);
      } catch (e) {
        print("Failed to initialize equalizer: $e");
        audioPlayer = AudioPlayer();
      }

      audioPlayer!.androidAudioSessionIdStream.listen((sessionId) async {
        if (sessionId != null && sessionId != 0) {
          try {
            const channel = MethodChannel('com.echonix.music/audio_effects');
            await channel.invokeMethod('initEffects', {'sessionId': sessionId});
            
            final prefs = await SharedPreferences.getInstance();
            final virtStrength = prefs.getInt('virtualizer_strength') ?? 0;
            final bassStrength = prefs.getInt('bass_boost_strength') ?? 0;
            await channel.invokeMethod('setVirtualizerStrength', {'strength': virtStrength});
            await channel.invokeMethod('setBassBoostStrength', {'strength': bassStrength});
          } catch (e) {
            print("Failed to initialize native audio effects: $e");
          }
        }
      });
    } else {
      audioPlayer = AudioPlayer();
    }

    // Read persisted shuffle state and apply to player
    SharedPreferences.getInstance().then((prefs) {
      final shuffleEnabled = prefs.getBool('shuffle_enabled') ?? false;
      ref.read(shuffleProvider.notifier).state = shuffleEnabled;
      audioPlayer!.setShuffleModeEnabled(shuffleEnabled);
    });

    // Read persisted repeat mode and apply to player (default LoopMode.off)
    SharedPreferences.getInstance().then((prefs) {
      final modeStr = prefs.getString('repeat_mode') ?? 'off';
      final mode = LoopMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => LoopMode.off,
      );
      ref.read(repeatModeProvider.notifier).state = mode;
      audioPlayer?.setLoopMode(mode);
    });

    // Listen to play/pause state
    audioPlayer!.playingStream.listen((playing) {
      isPlaying = playing;
    });

    audioPlayer!.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < playlist.length && index != currentSongIndex) {
        final song = playlist[index];
        currentSongIndex = index;
        state = song;
        _hasCountedForCurrentSong = false;
        _startListeningSignal(song);

        _homeLocalRepository.uploadLocalSong(song);
        _homeLocalRepository.recordRecentlyPlayed(song);
        ref.invalidate(recentlyPlayedProvider);

        final nextIndex = index + 1;
        if (nextIndex < playlist.length) {
          _redirectServer?.prefetch(playlist[nextIndex].id);
        }

        checkAutoplay();
      }
    });

    // Position-based tracker: min(30s, 50% duration)
    audioPlayer!.positionStream.listen((position) {
      if (position.inMilliseconds > _maxPositionMs) {
        _maxPositionMs = position.inMilliseconds;
      }
      if (_hasCountedForCurrentSong || state == null) return;

      final duration = audioPlayer?.duration;
      Duration threshold = const Duration(seconds: 30);
      if (duration != null && duration > Duration.zero) {
        final halfDuration = Duration(milliseconds: duration.inMilliseconds ~/ 2);
        if (halfDuration < threshold) {
          threshold = halfDuration;
        }
      }

      if (position >= threshold) {
        _hasCountedForCurrentSong = true;
        final song = state!;
        _homeLocalRepository.incrementPlayCount(song.id);
        _homeLocalRepository.recordPlaybackHistory(song);
        ref.read(syncServiceProvider.notifier).enqueue('history', {'videoId': song.id});
        ref.invalidate(listeningHistoryProvider);
      }
    });

    // Listen to playback completion and expose loading state
    audioPlayer!.processingStateStream.listen((processingState) {
      final isLoading = processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering;
      ref.read(isPlayerLoadingProvider.notifier).state = isLoading;

      if (processingState == ProcessingState.ready && _needsEqReapply) {
        _needsEqReapply = false;
        try {
          ref.read(equalizerProvider.notifier).reapplySettings();
        } catch (_) {}
      }

      if (processingState == ProcessingState.completed) {
        isPlaying = false;
        _hasCountedForCurrentSong = false;
        _recordListeningSignal(completed: true);
      }
    });
  }

  void cycleRepeatMode() async {
    if (audioPlayer == null) return;
    final current = ref.read(repeatModeProvider);
    final next = switch (current) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    ref.read(repeatModeProvider.notifier).state = next;
    await audioPlayer!.setLoopMode(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('repeat_mode', next.name);
  }

  AudioSource _buildAudioSource(SongModel song) {
    final tag = MediaItem(
      id: song.id,
      title: song.song_name,
      artist: song.artist,
      artUri: Uri.tryParse(song.thumbnail_url),
    );
    if (song.song_url.startsWith('/')) {
      return AudioSource.file(song.song_url, tag: tag);
    } else {
      if (song.id.length == 11) {
        final port = _redirectServer?.port ?? 8080;
        final token = _redirectServer?.serverToken ?? '';
        final localUrl = 'http://127.0.0.1:$port/play?id=${song.id}&t=$token';
        return AudioSource.uri(
          Uri.parse(localUrl),
          tag: tag,
          headers: const {
            'User-Agent': 'com.google.android.apps.youtube.music/5.28.1 (Linux; U; Android 11) gzip',
          },
        );
      }
      return AudioSource.uri(
        Uri.parse(song.song_url),
        tag: tag,
        headers: const {
          'User-Agent': 'com.google.android.apps.youtube.music/5.28.1 (Linux; U; Android 11) gzip',
        },
      );
    }
  }

  bool _notificationPermissionRequested = false;

  void updateSong(SongModel song) async {
    updatePlaylist([song], 0);
  }

  void updatePlaylist(List<SongModel> songs, int index) async {
    final requestId = ++_playRequestId;

    if (!_notificationPermissionRequested) {
      _notificationPermissionRequested = true;
      try {
        Permission.notification.request().catchError((_) => PermissionStatus.denied);
      } catch (_) {}
    }

    try {
      if (!_isServerStarted && _serverStartFuture != null) {
        await _serverStartFuture;
        if (requestId != _playRequestId) return;
      }

      _initAudioPlayer();
      try {
        await audioPlayer!.stop();
      } catch (_) {}
      if (requestId != _playRequestId) return;

      playlist = songs;
      _unshuffledPlaylist = null;
      currentSongIndex = index;
      final song = playlist[index];
      state = song;
      _hasCountedForCurrentSong = false;
      _startListeningSignal(song);

      _homeLocalRepository.uploadLocalSong(song);
      _homeLocalRepository.recordRecentlyPlayed(song);
      ref.invalidate(recentlyPlayedProvider);

      final nextIndex = index + 1;
      if (nextIndex < playlist.length) {
        _redirectServer?.prefetch(playlist[nextIndex].id);
      }

      // Build sequence using local redirect URLs for all YouTube songs
      final sources = <AudioSource>[];
      for (final s in playlist) {
        sources.add(_buildAudioSource(s));
      }

      _playlistSource = ConcatenatingAudioSource(children: sources);
      await audioPlayer!.setAudioSource(
        _playlistSource!,
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _needsEqReapply = true;
      if (requestId != _playRequestId) return;

      final repeatMode = ref.read(repeatModeProvider);
      await audioPlayer!.setLoopMode(repeatMode);
      if (requestId != _playRequestId) return;

      await audioPlayer!.play();
      isPlaying = true;
      checkAutoplay();
    } catch (e, st) {
      debugPrint("Echonix Playback Error: $e\n$st");
    }
  }

  void next() {
    if (audioPlayer != null && audioPlayer!.hasNext) {
      audioPlayer!.seekToNext();
    }
  }

  void previous() {
    if (audioPlayer != null && audioPlayer!.position > const Duration(seconds: 3)) {
      audioPlayer!.seek(Duration.zero);
      return;
    }
    if (audioPlayer != null && audioPlayer!.hasPrevious) {
      audioPlayer!.seekToPrevious();
    }
  }

  void playAtIndex(int index) {
    if (audioPlayer != null && index >= 0 && index < playlist.length) {
      audioPlayer!.seek(Duration.zero, index: index);
      audioPlayer!.play();
    }
  }

  void playPause() {
    if (audioPlayer != null) {
      if (audioPlayer!.playing) {
        audioPlayer!.pause();
      } else {
        audioPlayer!.play();
      }
    }
  }

  void seek(double val) {
    if (audioPlayer?.duration == null) return;
    audioPlayer!.seek(
      Duration(
        milliseconds: (val * audioPlayer!.duration!.inMilliseconds).toInt(),
      ),
    );
  }

  void addSongToQueue(SongModel song) {
    final manualSong = song.copyWith(isAutoplay: false);
    if (audioPlayer == null || playlist.isEmpty) {
      updateSong(manualSong);
      return;
    }
    playlist.add(manualSong);
    if (_playlistSource != null) {
      _playlistSource!.add(_buildAudioSource(manualSong));
    }
    ref.read(queueVersionProvider.notifier).state++;
  }

  void playNext(SongModel song) {
    final manualSong = song.copyWith(isAutoplay: false);
    if (audioPlayer == null || playlist.isEmpty) {
      updateSong(manualSong);
      return;
    }
    final insertIndex = currentSongIndex + 1;
    playlist.insert(insertIndex, manualSong);
    if (_playlistSource != null) {
      _playlistSource!.insert(insertIndex, _buildAudioSource(manualSong));
    }
    ref.read(queueVersionProvider.notifier).state++;
  }

  void removeSongFromQueue(int index) async {
    if (index < 0 || index >= playlist.length) return;
    if (index == currentSongIndex && isPlaying) return;

    final isRemovingCurrent = (index == currentSongIndex);

    playlist.removeAt(index);
    if (_unshuffledPlaylist != null) {
      _unshuffledPlaylist!.removeWhere((s) => !playlist.any((p) => p.id == s.id));
    }

    if (_playlistSource != null && index < _playlistSource!.length) {
      await _playlistSource!.removeAt(index);
    }

    if (playlist.isEmpty) {
      currentSongIndex = -1;
      state = null;
      isPlaying = false;
      await audioPlayer?.stop();
      ref.read(queueVersionProvider.notifier).state++;
      return;
    }

    if (isRemovingCurrent) {
      if (currentSongIndex < playlist.length) {
        state = playlist[currentSongIndex];
        _hasCountedForCurrentSong = false;
        await audioPlayer?.seek(Duration.zero, index: currentSongIndex);
      } else {
        currentSongIndex = playlist.length - 1;
        state = playlist[currentSongIndex];
        _hasCountedForCurrentSong = false;
        await audioPlayer?.seek(Duration.zero, index: currentSongIndex);
      }
    } else if (index < currentSongIndex) {
      currentSongIndex--;
    }
    ref.read(queueVersionProvider.notifier).state++;
    checkAutoplay();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= playlist.length) return;
    if (newIndex < 0 || newIndex > playlist.length) return;
    if (oldIndex == newIndex) return;

    final song = playlist.removeAt(oldIndex);
    if (newIndex > oldIndex) {
      newIndex--;
    }
    playlist.insert(newIndex, song);

    if (_playlistSource != null) {
      _playlistSource!.move(oldIndex, newIndex);
    }

    if (currentSongIndex == oldIndex) {
      currentSongIndex = newIndex;
    } else {
      if (oldIndex < currentSongIndex && newIndex >= currentSongIndex) {
        currentSongIndex--;
      } else if (oldIndex > currentSongIndex && newIndex <= currentSongIndex) {
        currentSongIndex++;
      }
    }
    ref.read(queueVersionProvider.notifier).state++;
  }

  void toggleShuffle() async {
    if (audioPlayer == null) return;
    final current = ref.read(shuffleProvider);
    final newVal = !current;
    ref.read(shuffleProvider.notifier).state = newVal;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shuffle_enabled', newVal);

    if (newVal) {
      _unshuffledPlaylist = List<SongModel>.from(playlist);

      if (playlist.length > currentSongIndex + 1 && currentSongIndex >= 0) {
        final prefix = playlist.sublist(0, currentSongIndex + 1);
        final rest = List<SongModel>.from(playlist.sublist(currentSongIndex + 1));

        final rand = Random();
        for (int i = rest.length - 1; i > 0; i--) {
          final j = rand.nextInt(i + 1);
          final temp = rest[i];
          rest[i] = rest[j];
          rest[j] = temp;
        }

        playlist = [...prefix, ...rest];

        if (_playlistSource != null) {
          while (_playlistSource!.length > currentSongIndex + 1) {
            await _playlistSource!.removeAt(_playlistSource!.length - 1);
          }
          await _playlistSource!.addAll(rest.map(_buildAudioSource).toList());
        }
      }
    } else {
      if (_unshuffledPlaylist != null && _unshuffledPlaylist!.isNotEmpty) {
        final original = _unshuffledPlaylist!;
        _unshuffledPlaylist = null;

        final currentSong = state;
        final currentSongId = currentSong?.id;

        final restFromOriginal = original.where((s) {
          return playlist.any((p) => p.id == s.id) && s.id != currentSongId;
        }).toList();

        final prefix = playlist.sublist(0, currentSongIndex + 1);
        playlist = [...prefix, ...restFromOriginal];

        if (_playlistSource != null) {
          while (_playlistSource!.length > currentSongIndex + 1) {
            await _playlistSource!.removeAt(_playlistSource!.length - 1);
          }
          await _playlistSource!.addAll(restFromOriginal.map(_buildAudioSource).toList());
        }
      }
    }
    ref.read(queueVersionProvider.notifier).state++;
  }
}

// -----------------------------------------------------------------------------
// Sleep Timer (Bedtime Mode) Notifier & Provider
// -----------------------------------------------------------------------------

class SleepTimerNotifier extends StateNotifier<int> {
  final Ref _ref;
  Timer? _timer;

  SleepTimerNotifier(this._ref) : super(0);

  void setTimer(int minutes) {
    _timer?.cancel();
    if (minutes <= 0) {
      state = 0;
      return;
    }
    state = minutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state <= 1) {
        state = 0;
        _timer?.cancel();
        _ref.read(currentSongNotifierProvider.notifier).audioPlayer?.pause();
      } else {
        state = state - 1;
      }
    });
  }

  void stopTimer() {
    _timer?.cancel();
    state = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, int>((ref) {
  return SleepTimerNotifier(ref);
});

// -----------------------------------------------------------------------------
// Equalizer Settings, Notifier & Provider
// -----------------------------------------------------------------------------
class EqualizerSettings {
  final bool enabled;
  final String preset; // "Normal", "Bass Boost", "Pop", "Rock", "Classical", "Jazz", "Custom", or user-defined custom names
  final List<double> customGains; // Dynamic bands gains
  final List<double> frequencies; // Center frequencies in Hz
  final Map<String, List<double>> customPresets;
  final int virtualizerStrength; // 0 to 1000
  final int bassBoostStrength; // 0 to 1000

  EqualizerSettings({
    required this.enabled,
    required this.preset,
    required this.customGains,
    required this.frequencies,
    required this.customPresets,
    required this.virtualizerStrength,
    required this.bassBoostStrength,
  });

  EqualizerSettings copyWith({
    bool? enabled,
    String? preset,
    List<double>? customGains,
    List<double>? frequencies,
    Map<String, List<double>>? customPresets,
    int? virtualizerStrength,
    int? bassBoostStrength,
  }) {
    return EqualizerSettings(
      enabled: enabled ?? this.enabled,
      preset: preset ?? this.preset,
      customGains: customGains ?? this.customGains,
      frequencies: frequencies ?? this.frequencies,
      customPresets: customPresets ?? this.customPresets,
      virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
      bassBoostStrength: bassBoostStrength ?? this.bassBoostStrength,
    );
  }
}

class EqualizerNotifier extends StateNotifier<EqualizerSettings> {
  final Ref _ref;

  EqualizerNotifier(this._ref)
      : super(EqualizerSettings(
          enabled: false,
          preset: 'Normal',
          customGains: [0.0, 0.0, 0.0, 0.0, 0.0],
          frequencies: [60.0, 230.0, 910.0, 4000.0, 14000.0],
          customPresets: {},
          virtualizerStrength: 0,
          bassBoostStrength: 0,
        )) {
    _loadPresets();
    _initFrequencies();
  }

  Future<void> _initFrequencies() async {
    // Wait a brief moment for AudioPlayer to bind to underlying OS services
    await Future.delayed(const Duration(milliseconds: 500));
    final playerNotifier = _ref.read(currentSongNotifierProvider.notifier);
    final eq = playerNotifier._equalizer;
    if (eq == null) return;
    try {
      final params = await eq.parameters;
      final bands = params.bands;
      final List<double> freqs = [];
      for (var b in bands) {
        freqs.add(b.centerFrequency);
      }
      if (freqs.isNotEmpty) {
        final currentGains = state.customGains;
        final List<double> newGains = List.generate(
          freqs.length,
          (i) => i < currentGains.length ? currentGains[i] : 0.0,
        );
        state = state.copyWith(
          frequencies: freqs,
          customGains: newGains,
        );
        _applySettings();
      }
    } catch (_) {}
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_eq_presets');
    final virtStrength = prefs.getInt('virtualizer_strength') ?? 0;
    final bassStrength = prefs.getInt('bass_boost_strength') ?? 0;
    final eqEnabled = prefs.getBool('eq_enabled') ?? false;
    final eqPreset = prefs.getString('eq_preset') ?? 'Normal';
    final customGainsStr = prefs.getString('eq_custom_gains');

    Map<String, List<double>> loaded = {};
    if (data != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(data);
        decoded.forEach((key, val) {
          loaded[key] = List<double>.from((val as List).map((e) => (e as num).toDouble()));
        });
      } catch (_) {}
    }

    List<double> loadedCustomGains = state.customGains;
    if (customGainsStr != null) {
      try {
        loadedCustomGains = List<double>.from(
          (jsonDecode(customGainsStr) as List).map((e) => (e as num).toDouble()),
        );
      } catch (_) {}
    }

    state = state.copyWith(
      enabled: eqEnabled,
      preset: eqPreset,
      customGains: loadedCustomGains,
      customPresets: loaded,
      virtualizerStrength: virtStrength,
      bassBoostStrength: bassStrength,
    );
    _applySettings();
  }

  Future<void> saveCustomPreset(String name) async {
    if (name.trim().isEmpty) return;
    final newPresets = Map<String, List<double>>.from(state.customPresets);
    newPresets[name.trim()] = List<double>.from(state.customGains);
    state = state.copyWith(customPresets: newPresets, preset: name.trim());
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_eq_presets', jsonEncode(newPresets));
  }

  Future<void> deleteCustomPreset(String name) async {
    final newPresets = Map<String, List<double>>.from(state.customPresets);
    newPresets.remove(name);
    state = state.copyWith(
      customPresets: newPresets,
      preset: state.preset == name ? 'Normal' : state.preset,
    );
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_eq_presets', jsonEncode(newPresets));
    _applySettings();
  }

  void toggle(bool val) {
    state = state.copyWith(enabled: val);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('eq_enabled', val);
    });
    _applySettings();
  }

  void setPreset(String preset) {
    state = state.copyWith(preset: preset);
    if (state.customPresets.containsKey(preset)) {
      final loadedGains = state.customPresets[preset]!;
      final List<double> newGains = List.generate(
        state.frequencies.length,
        (i) => i < loadedGains.length ? loadedGains[i] : 0.0,
      );
      state = state.copyWith(customGains: newGains);
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('eq_preset', preset);
    });
    _applySettings();
  }

  void setBand(int bandIdx, double gain) {
    final newGains = List<double>.from(state.customGains);
    if (bandIdx >= 0 && bandIdx < newGains.length) {
      newGains[bandIdx] = gain;
    }
    state = state.copyWith(preset: 'Custom', customGains: newGains);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('eq_custom_gains', jsonEncode(newGains));
      prefs.setString('eq_preset', 'Custom');
    });
    _applySettings();
  }

  void reapplySettings() {
    _applySettings();
  }

  void _applySettings() async {
    final playerNotifier = _ref.read(currentSongNotifierProvider.notifier);
    final eq = playerNotifier._equalizer;
    if (eq == null) return;

    try {
      if (!state.enabled) {
        await eq.setEnabled(false);
        return;
      }
      await eq.setEnabled(true);
      
      List<double> gains = [];
      if (state.customPresets.containsKey(state.preset)) {
        final loadedGains = state.customPresets[state.preset]!;
        gains = List.generate(
          state.frequencies.length,
          (i) => i < loadedGains.length ? loadedGains[i] : 0.0,
        );
      } else {
        switch (state.preset) {
          case 'Normal':
            gains = List.filled(state.frequencies.length, 0.0);
            break;
          case 'Bass Boost':
            gains = List.generate(state.frequencies.length, (i) => i < 2 ? (5.0 - i * 2.0) : 0.0);
            break;
          case 'Pop':
            gains = List.generate(state.frequencies.length, (i) => [1.0, 2.0, 3.0, 1.0, -1.0][i % 5]);
            break;
          case 'Rock':
            gains = List.generate(state.frequencies.length, (i) => [3.0, 1.0, -2.0, 2.0, 4.0][i % 5]);
            break;
          case 'Classical':
            gains = List.generate(state.frequencies.length, (i) => [4.0, 2.0, 0.0, 2.0, 3.0][i % 5]);
            break;
          case 'Jazz':
            gains = List.generate(state.frequencies.length, (i) => [3.0, 2.0, -1.0, 2.0, 1.0][i % 5]);
            break;
          case 'Custom':
          default:
            gains = state.customGains;
            break;
        }
      }

      final params = await eq.parameters;
      final minDb = params.minDecibels;
      final maxDb = params.maxDecibels;
      final bands = params.bands;
      for (int i = 0; i < gains.length && i < bands.length; i++) {
        final clampedGain = gains[i].clamp(minDb, maxDb);
        await bands[i].setGain(clampedGain);
      }
    } catch (e) {
      print("Error applying EQ settings: $e");
    }
  }

  Future<void> setVirtualizerStrength(int strength) async {
    state = state.copyWith(virtualizerStrength: strength);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('virtualizer_strength', strength);
    
    try {
      const channel = MethodChannel('com.echonix.music/audio_effects');
      await channel.invokeMethod('setVirtualizerStrength', {'strength': strength});
    } catch (e) {
      print("Failed to set native virtualizer strength: $e");
    }
  }

  Future<void> setBassBoostStrength(int strength) async {
    state = state.copyWith(bassBoostStrength: strength);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bass_boost_strength', strength);
    
    try {
      const channel = MethodChannel('com.echonix.music/audio_effects');
      await channel.invokeMethod('setBassBoostStrength', {'strength': strength});
    } catch (e) {
      print("Failed to set native bass boost strength: $e");
    }
  }
}

final equalizerProvider = StateNotifierProvider<EqualizerNotifier, EqualizerSettings>((ref) {
  return EqualizerNotifier(ref);
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  final player = ref.watch(currentSongNotifierProvider.notifier).audioPlayer;
  if (player == null) return const Stream.empty();
  return player.playingStream;
});
