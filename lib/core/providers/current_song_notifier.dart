import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/core/python_backend.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
part 'current_song_notifier.g.dart';

final shuffleProvider = StateProvider<bool>((ref) => false);

class LocalRedirectServer {
  HttpServer? _server;
  int get port => _server?.port ?? 8080;
  
  // Cache for resolved stream URLs to make seeking instantaneous
  final Map<String, _CachedUrl> _cache = {};

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen((HttpRequest request) async {
        final videoId = request.uri.queryParameters['id'];
        if (videoId == null || videoId.isEmpty) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        // Check cache first
        final cached = _cache[videoId];
        if (cached != null && DateTime.now().isBefore(cached.expiry)) {
          final url = cached.url;
          if (url.startsWith('/')) {
            final file = File(url);
            if (await file.exists()) {
              request.response.headers.contentType = ContentType('audio', 'mpeg');
              await file.openRead().pipe(request.response);
              return;
            }
          } else {
            request.response.statusCode = HttpStatus.movedTemporarily;
            request.response.headers.set(HttpHeaders.locationHeader, url);
            await request.response.close();
            return;
          }
        }

        // Fetch stream URL from YT Music python backend
        final res = await PythonBackend.getStreamUrl(videoId);
        if (res['success'] == true) {
          final url = res['url'] as String?;
          if (url != null && url.isNotEmpty) {
            // Cache the url for 1 hour
            _cache[videoId] = _CachedUrl(url, DateTime.now().add(const Duration(hours: 1)));

            if (url.startsWith('/')) {
              // Local file: serve directly
              final file = File(url);
              if (await file.exists()) {
                request.response.headers.contentType = ContentType('audio', 'mpeg');
                await file.openRead().pipe(request.response);
                return;
              }
            } else {
              // Remote stream: 302 redirect
              request.response.statusCode = HttpStatus.movedTemporarily;
              request.response.headers.set(HttpHeaders.locationHeader, url);
              await request.response.close();
              return;
            }
          }
        }

        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });
    } catch (e, st) {
      print("LocalRedirectServer Bind Error: $e");
      print(st);
    }
  }

  void stop() {
    _server?.close();
    _server = null;
    _cache.clear();
  }
}

class _CachedUrl {
  final String url;
  final DateTime expiry;
  _CachedUrl(this.url, this.expiry);
}

@Riverpod(keepAlive: true)
class CurrentSongNotifier extends _$CurrentSongNotifier {
  late HomeLocalRepository _homeLocalRepository;
  AudioPlayer? audioPlayer;
  AndroidEqualizer? _equalizer;
  bool isPlaying = false;
  List<SongModel> playlist = [];
  int currentSongIndex = -1;
  bool _isLoading = false;

  ConcatenatingAudioSource? _playlistSource;
  LocalRedirectServer? _redirectServer;
  Future<void>? _serverStartFuture;

  @override
  SongModel? build() {
    _homeLocalRepository = ref.watch(homeLocalRepositoryProvider);
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
    _serverStartFuture = _redirectServer!.start();
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
    } else {
      audioPlayer = AudioPlayer();
    }

    // Read persisted shuffle state and apply to player
    SharedPreferences.getInstance().then((prefs) {
      final shuffleEnabled = prefs.getBool('shuffle_enabled') ?? false;
      ref.read(shuffleProvider.notifier).state = shuffleEnabled;
      audioPlayer!.setShuffleModeEnabled(shuffleEnabled);
    });

    // Listen to play/pause state
    audioPlayer!.playingStream.listen((playing) {
      isPlaying = playing;
      if (state != null) {
        state = state!.copyWith(hex_code: state!.hex_code);
      }
    });

    audioPlayer!.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < playlist.length && index != currentSongIndex) {
        final song = playlist[index];
        currentSongIndex = index;
        state = song;

        _homeLocalRepository.uploadLocalSong(song);
        _homeLocalRepository.recordRecentlyPlayed(song);
        _homeLocalRepository.recordPlaybackHistory(song);
        PythonBackend.addHistory(song.id);
        ref.invalidate(recentlyPlayedProvider);
        ref.invalidate(listeningHistoryProvider);
      }
    });

    // Listen to playback completion
    audioPlayer!.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        isPlaying = false;
        if (state != null) {
          state = state!.copyWith(hex_code: state!.hex_code);
          _homeLocalRepository.incrementPlayCount(state!.id);
        }
      }
    });
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
        final localUrl = 'http://127.0.0.1:$port/play?id=${song.id}';
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

  void updateSong(SongModel song) async {
    updatePlaylist([song], 0);
  }

  void updatePlaylist(List<SongModel> songs, int index) async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      if (_serverStartFuture != null) {
        await _serverStartFuture;
      }

      _initAudioPlayer();
      // Do not await stop() here to prevent deadlocks when switching tracks while playing.
      // Pausing tells the engine to stop playing the active stream immediately.
      audioPlayer!.pause();

      playlist = songs;
      currentSongIndex = index;
      final song = playlist[index];
      state = song;

      _homeLocalRepository.recordRecentlyPlayed(song);
      _homeLocalRepository.recordPlaybackHistory(song);
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(listeningHistoryProvider);

      // Build sequence using local redirect URLs for all YouTube songs
      final sources = <AudioSource>[];
      for (final s in playlist) {
        sources.add(_buildAudioSource(s));
      }

      _playlistSource = ConcatenatingAudioSource(children: sources);
      await audioPlayer!.setAudioSource(_playlistSource!, initialIndex: index, initialPosition: Duration.zero);
      await audioPlayer!.setLoopMode(LoopMode.all);

      await audioPlayer!.play();
      isPlaying = true;
    } catch (e, st) {
      // Print fully to console so we can trace playback failures
      print("Echonix Playback Error: $e");
      print(st);
    } finally {
      _isLoading = false;
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
    if (audioPlayer == null || playlist.isEmpty) {
      updateSong(song);
      return;
    }
    playlist.add(song);
    if (_playlistSource != null) {
      _playlistSource!.add(_buildAudioSource(song));
    }
  }

  void playNext(SongModel song) {
    if (audioPlayer == null || playlist.isEmpty) {
      updateSong(song);
      return;
    }
    final insertIndex = currentSongIndex + 1;
    playlist.insert(insertIndex, song);
    if (_playlistSource != null) {
      _playlistSource!.insert(insertIndex, _buildAudioSource(song));
    }
  }

  void removeSongFromQueue(int index) {
    if (index < 0 || index >= playlist.length) return;
    if (index == currentSongIndex && isPlaying) return;

    playlist.removeAt(index);
    if (_playlistSource != null) {
      _playlistSource!.removeAt(index);
    }
    if (index < currentSongIndex) {
      currentSongIndex--;
    }
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
  }

  void toggleShuffle() {
    if (audioPlayer == null) return;
    final current = ref.read(shuffleProvider);
    final newVal = !current;
    ref.read(shuffleProvider.notifier).state = newVal;
    audioPlayer!.setShuffleModeEnabled(newVal);

    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('shuffle_enabled', newVal);
    });
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

  EqualizerSettings({
    required this.enabled,
    required this.preset,
    required this.customGains,
    required this.frequencies,
    required this.customPresets,
  });

  EqualizerSettings copyWith({
    bool? enabled,
    String? preset,
    List<double>? customGains,
    List<double>? frequencies,
    Map<String, List<double>>? customPresets,
  }) {
    return EqualizerSettings(
      enabled: enabled ?? this.enabled,
      preset: preset ?? this.preset,
      customGains: customGains ?? this.customGains,
      frequencies: frequencies ?? this.frequencies,
      customPresets: customPresets ?? this.customPresets,
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
        state = state.copyWith(
          frequencies: freqs,
          customGains: List.filled(freqs.length, 0.0),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('custom_eq_presets');
    if (data != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(data);
        final Map<String, List<double>> loaded = {};
        decoded.forEach((key, val) {
          loaded[key] = List<double>.from((val as List).map((e) => (e as num).toDouble()));
        });
        state = state.copyWith(customPresets: loaded);
      } catch (_) {}
    }
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
    _applySettings();
  }

  void setBand(int bandIdx, double gain) {
    final newGains = List<double>.from(state.customGains);
    if (bandIdx >= 0 && bandIdx < newGains.length) {
      newGains[bandIdx] = gain;
    }
    state = state.copyWith(preset: 'Custom', customGains: newGains);
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
      final bands = params.bands;
      for (int i = 0; i < gains.length && i < bands.length; i++) {
        await bands[i].setGain(gains[i] * 100);
      }
    } catch (e) {
      print("Error applying EQ settings: $e");
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
