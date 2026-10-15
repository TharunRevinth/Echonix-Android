import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/dominant_color_provider.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/theme/glass.dart';
import 'package:client/core/utils.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/view/pages/queue_page.dart';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:client/features/home/viewmodel/downloads_notifier.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';

class MusicPlayer extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final double? dragProgress;
  final ValueChanged<double>? onVerticalDragUpdate;
  final ValueChanged<double>? onVerticalDragEnd;

  const MusicPlayer({
    super.key,
    this.onClose,
    this.dragProgress,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  @override
  ConsumerState<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends ConsumerState<MusicPlayer> {
  List<_LyricLine> _syncedLines = [];
  List<GlobalKey> _lyricKeys = [];
  String _plainLyrics = '';
  bool _lyricsLoading = false;
  String? _lyricsLoadedFor;
  final ScrollController _lyricsScroll = ScrollController();
  int _currentLyricIndex = 0;
  Timer? _lyricTimer;
  int _lyricsOffsetMs = 0;
  bool _showLyrics = false;

  bool _userScrolling = false;
  Timer? _userScrollEndTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentSong = ref.read(currentSongNotifierProvider);
      if (currentSong != null) {
        _loadLyrics(currentSong);
      }
    });
  }

  @override
  void dispose() {
    _lyricsScroll.dispose();
    _lyricTimer?.cancel();
    _userScrollEndTimer?.cancel();
    super.dispose();
  }

  void _applyLyrics(String lyrics, bool isSynced, String songId) {
    if (!mounted) return;
    if (isSynced) {
      final lines = _parseLrc(lyrics);
      setState(() {
        _syncedLines = lines;
        _lyricKeys = List.generate(lines.length, (_) => GlobalKey());
        _lyricsLoading = false;
        _lyricsLoadedFor = songId;
      });
      _startLyricSync();
    } else {
      setState(() {
        _plainLyrics = lyrics;
        _lyricsLoading = false;
        _lyricsLoadedFor = songId;
      });
    }
  }

  void _loadLyrics(SongModel song) async {
    final songId = song.id;
    if (_lyricsLoadedFor == songId) return;

    setState(() {
      _lyricsLoading = true;
      _syncedLines = [];
      _lyricKeys = [];
      _plainLyrics = '';
      _lyricsLoadedFor = songId;
      _lyricsOffsetMs = 0;
    });

    final Box box = Hive.box();
    final dynamic rawCache = box.get('lyrics_cache');
    final Map<String, dynamic> cache =
        rawCache is Map ? Map<String, dynamic>.from(rawCache) : {};

    // 1. Look in cache before the network
    if (cache.containsKey(songId)) {
      final item = cache[songId];
      if (item is Map) {
        final synced = item['synced'] == true;
        final lyrics = item['lyrics'] as String? ?? '';
        if (lyrics.isNotEmpty) {
          cache.remove(songId);
          cache[songId] = item;
          box.put('lyrics_cache', cache);
          _applyLyrics(lyrics, synced, songId);
          return;
        }
      }
    }

    // 2. Try to load offline lyrics first if song_url is a local path
    if (song.song_url.startsWith('/')) {
      final metaFile = File('${song.song_url}.json');
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          final meta = jsonDecode(content);
          if (meta is Map && meta.containsKey('lyrics')) {
            final lyrics = meta['lyrics'] as String? ?? '';
            final isSynced = meta['synced_lyrics'] == true;
            if (lyrics.isNotEmpty) {
              _applyLyrics(lyrics, isSynced, songId);
              return;
            }
          }
        } catch (_) {}
      }
    }

    // 3. Fallback to network with duration
    try {
      final res = await PythonBackend.getLyrics(
        song.song_name,
        song.artist,
        durationSeconds: song.duration_seconds,
      );

      if (_lyricsLoadedFor != songId) return;

      if (res['success'] == true) {
        final bool synced = res['synced'] == true;
        final String lyrics = res['lyrics'] ?? '';

        cache[songId] = {'synced': synced, 'lyrics': lyrics};
        if (cache.length > 100) {
          cache.remove(cache.keys.first);
        }
        box.put('lyrics_cache', cache);

        _applyLyrics(lyrics, synced, songId);
      } else {
        setState(() {
          _lyricsLoading = false;
          _plainLyrics = 'No lyrics found for this song.';
        });
      }
    } catch (e) {
      if (_lyricsLoadedFor != songId) return;
      setState(() {
        _lyricsLoading = false;
        _plainLyrics = 'Failed to load lyrics.';
      });
    }
  }

  List<_LyricLine> _parseLrc(String lrc) {
    final List<_LyricLine> lines = [];
    final re = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$');
    for (final line in lrc.split('\n')) {
      final m = re.firstMatch(line.trim());
      if (m != null) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final cs = int.parse(m.group(3)!.padRight(2, '0').substring(0, 2));
        final ms = (min * 60 + sec) * 1000 + cs * 10;
        final text = m.group(4)!.trim();
        if (text.isNotEmpty) lines.add(_LyricLine(ms, text));
      }
    }
    lines.sort((a, b) => a.ms.compareTo(b.ms));
    return lines;
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _userScrollEndTimer?.cancel();
        setState(() {
          _userScrolling = true;
        });
      }
    } else if (notification is ScrollEndNotification) {
      _userScrollEndTimer?.cancel();
      _userScrollEndTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _userScrolling = false;
          });
          _scrollToLyric(_currentLyricIndex);
        }
      });
    }
  }

  void _startLyricSync() {
    _lyricTimer?.cancel();
    _lyricTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final notifier = ref.read(currentSongNotifierProvider.notifier);
      final pos = notifier.audioPlayer?.position;
      if (pos == null || _syncedLines.isEmpty) return;
      final ms = pos.inMilliseconds + _lyricsOffsetMs;
      int idx = 0;
      for (int i = 0; i < _syncedLines.length; i++) {
        if (_syncedLines[i].ms <= ms) idx = i;
      }
      if (idx != _currentLyricIndex && mounted) {
        setState(() => _currentLyricIndex = idx);
        if (!_userScrolling) {
          _scrollToLyric(idx);
        }
      }
    });
  }

  void _scrollToLyric(int index) {
    if (index < 0 || index >= _lyricKeys.length) return;
    final key = _lyricKeys[index];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    }
  }

  String _formatOffset(int ms) {
    if (ms == 0) return '0s';
    final sign = ms > 0 ? '+' : '-';
    final abs = ms.abs();
    final sec = abs ~/ 1000;
    final dec = ((abs % 1000) / 100).round();
    return '$sign$sec.${dec}s';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: const GlassSurface(
            borderRadius: 28,
            blurSigma: 28,
            child: QueuePage(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongNotifierProvider);
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);
    final isLiked = currentSong != null &&
        ref.watch(
          likedSongIdsProvider.select((ids) => ids.contains(currentSong.id)),
        );

    ref.listen<SongModel?>(currentSongNotifierProvider, (previous, next) {
      if (next != null) {
        _loadLyrics(next);
      }
    });

    if (currentSong == null) return const SizedBox();

    final hqThumbnail = getHighQualityThumbnail(currentSong.thumbnail_url);
    final dynColor = ref.watch(dominantColorProvider(hqThumbnail)).valueOrNull ??
        hexToColor(currentSong.hex_code);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        widget.onVerticalDragUpdate?.call(details.primaryDelta ?? 0.0);
      },
      onVerticalDragEnd: (details) {
        widget.onVerticalDragEnd?.call(details.primaryVelocity ?? 0.0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: const Color(0xFF09060E),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              dynColor.withOpacity(0.55),
              dynColor.withOpacity(0.20),
              Colors.black,
            ],
            stops: const [0.0, 0.45, 0.9],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  // 1. Grab Handle
                  GestureDetector(
                    onTap: widget.onClose ?? () => Navigator.maybePop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  // 2. Artwork & Lyrics cross-fade area
                  Expanded(
                    child: Center(
                      child: AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        firstCurve: Curves.easeOutCubic,
                        secondCurve: Curves.easeOutCubic,
                        crossFadeState: _showLyrics
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: _buildArtworkView(context, hqThumbnail, dynColor),
                        secondChild: _buildLyricsView(context, dynColor),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Title, Artist, Like Heart, Menu
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong.song_name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentSong.album != null && currentSong.album!.isNotEmpty
                                  ? '${currentSong.artist} • ${currentSong.album}'
                                  : currentSong.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.65),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          ref.read(likedSongIdsProvider.notifier).toggle(currentSong);
                        },
                        icon: Icon(
                          isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                          color: isLiked ? Colors.redAccent : Colors.white,
                          size: 26,
                        ),
                      ),
                      DownloadButton(
                        song: currentSong,
                        size: 24,
                        color: Colors.white70,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white70),
                        color: const Color(0xFF1E1428),
                        onSelected: (val) {
                          if (val == 'queue') {
                            _openQueueSheet(context);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'queue',
                            child: Text('View Queue', style: TextStyle(color: Colors.white)),
                          ),
                          PopupMenuItem(
                            enabled: false,
                            child: Text(
                              'Album: ${currentSong.album ?? 'Single'}',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 4. Progress bar with times
                  StreamBuilder<Duration>(
                    stream: songNotifier.audioPlayer?.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final totalDuration = songNotifier.audioPlayer?.duration ??
                          Duration(seconds: currentSong.duration_seconds ?? 0);

                      final double maxMs = totalDuration.inMilliseconds > 0
                          ? totalDuration.inMilliseconds.toDouble()
                          : 1.0;
                      final double currentMs =
                          position.inMilliseconds.toDouble().clamp(0.0, maxMs);

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              thumbShape:
                                  const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                              overlayShape:
                                  const RoundSliderOverlayShape(overlayRadius: 14.0),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withOpacity(0.15),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: currentMs,
                              min: 0.0,
                              max: maxMs,
                              onChanged: (val) {
                                songNotifier.seek(val / maxMs);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 12,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  _formatDuration(totalDuration),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 12,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // 5. Transport Row (shuffle, previous, play/pause, next, repeat)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: songNotifier.toggleShuffle,
                        icon: Icon(
                          CupertinoIcons.shuffle,
                          color: ref.watch(shuffleProvider) ? Colors.white : Colors.white30,
                          size: 22,
                        ),
                      ),
                      IconButton(
                        onPressed: songNotifier.previous,
                        icon: const Icon(
                          CupertinoIcons.backward_fill,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      GestureDetector(
                        onTap: songNotifier.playPause,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: ref.watch(isPlayerLoadingProvider)
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : Icon(
                                    ref.watch(isPlayingProvider).value ?? false
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    color: Colors.black,
                                    size: 34,
                                  ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: songNotifier.next,
                        icon: const Icon(
                          CupertinoIcons.forward_fill,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      IconButton(
                        onPressed: songNotifier.cycleRepeatMode,
                        icon: Icon(
                          ref.watch(repeatModeProvider) == LoopMode.one
                              ? CupertinoIcons.repeat_1
                              : CupertinoIcons.repeat,
                          color: ref.watch(repeatModeProvider) != LoopMode.off
                              ? Colors.white
                              : Colors.white30,
                          size: 22,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 6. Bottom Row: lyrics, queue, sleep timer, EQ
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showLyrics = !_showLyrics;
                            });
                          },
                          icon: Icon(
                            Icons.lyrics_outlined,
                            color: _showLyrics ? Colors.white : Colors.white38,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _openQueueSheet(context),
                          icon: const Icon(
                            Icons.queue_music_rounded,
                            color: Colors.white70,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            // Quick toggle bedtime sleep timer dialog
                            _showSleepTimerDialog(context);
                          },
                          icon: Icon(
                            ref.watch(sleepTimerProvider) > 0
                                ? Icons.bedtime_rounded
                                : Icons.bedtime_outlined,
                            color: ref.watch(sleepTimerProvider) > 0
                                ? Colors.blueAccent
                                : Colors.white70,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _showEqualizerDialog(context);
                          },
                          icon: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white70,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtworkView(BuildContext context, String hqThumbnail, Color dynColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final size = screenWidth * 0.80;

    return Center(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showLyrics = true;
          });
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: dynColor.withOpacity(0.35),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: hqThumbnail,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF201826),
                child: const Icon(Icons.music_note, color: Colors.white54, size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context, Color dynColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final size = screenWidth * 0.85;

    final effectsMode = ref.watch(visualEffectsModeProvider);
    final isReduced = effectsMode == VisualEffectsMode.reduced ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return Container(
      width: size,
      height: size + 40,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Lyrics',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Row(
                children: [
                  PopupMenuButton<int>(
                    icon: Icon(
                      Icons.tune,
                      color: _lyricsOffsetMs != 0 ? Colors.blueAccent : Colors.white54,
                      size: 20,
                    ),
                    color: const Color(0xFF1E1428),
                    onSelected: (delta) {
                      setState(() {
                        if (delta == 0) {
                          _lyricsOffsetMs = 0;
                        } else {
                          _lyricsOffsetMs += delta;
                        }
                      });
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          'Offset: ${_formatOffset(_lyricsOffsetMs)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const PopupMenuItem(value: -500, child: Text('-0.5s Earlier', style: TextStyle(color: Colors.white70))),
                      const PopupMenuItem(value: 500, child: Text('+0.5s Later', style: TextStyle(color: Colors.white70))),
                      const PopupMenuItem(value: 0, child: Text('Reset', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () {
                      setState(() {
                        _showLyrics = false;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: _lyricsLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _syncedLines.isNotEmpty
                    ? NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          _onScrollNotification(n);
                          return false;
                        },
                        child: ListView.builder(
                          controller: _lyricsScroll,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          itemCount: _syncedLines.length,
                          itemBuilder: (context, index) {
                            final line = _syncedLines[index];
                            final isActive = index == _currentLyricIndex;
                            final distance = (index - _currentLyricIndex).abs();
                            final blurSigma = isReduced ? 0.0 : (distance * 0.6).clamp(0.0, 2.0);

                            Widget lyricText = Text(
                              line.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white.withOpacity(0.45),
                                fontSize: isActive ? 21 : 16,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                height: 1.6,
                              ),
                            );

                            if (blurSigma > 0.0) {
                              lyricText = ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                                child: lyricText,
                              );
                            }

                            return GestureDetector(
                              key: _lyricKeys[index],
                              onTap: () {
                                final targetMs = (line.ms - _lyricsOffsetMs).clamp(0, 9999999);
                                ref.read(currentSongNotifierProvider.notifier).audioPlayer?.seek(
                                      Duration(milliseconds: targetMs),
                                    );
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                                child: lyricText,
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          child: Text(
                            _plainLyrics.isNotEmpty ? _plainLyrics : 'No lyrics available.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.8),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showSleepTimerDialog(BuildContext context) {
    final timerNotifier = ref.read(sleepTimerProvider.notifier);
    final remaining = ref.read(sleepTimerProvider);
    final hasTimer = remaining > 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassSurface(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasTimer ? 'Sleep Timer Active (${(remaining / 60).ceil()}m left)' : 'Set Sleep Timer',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              if (hasTimer) ...[
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined, color: Colors.redAccent),
                  title: const Text('Cancel Timer', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    timerNotifier.setTimer(0);
                    Navigator.pop(context);
                  },
                ),
              ],
              ListTile(
                title: const Text('15 Minutes', style: TextStyle(color: Colors.white)),
                onTap: () {
                  timerNotifier.setTimer(15);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('30 Minutes', style: TextStyle(color: Colors.white)),
                onTap: () {
                  timerNotifier.setTimer(30);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('45 Minutes', style: TextStyle(color: Colors.white)),
                onTap: () {
                  timerNotifier.setTimer(45);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('60 Minutes', style: TextStyle(color: Colors.white)),
                onTap: () {
                  timerNotifier.setTimer(60);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEqualizerDialog(BuildContext context) {
    final eq = ref.watch(equalizerProvider);
    final eqNotifier = ref.read(equalizerProvider.notifier);

    final presets = ['Normal', 'Bass Boost', 'Pop', 'Rock', 'Classical', 'Jazz', 'Custom'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassSurface(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Equalizer Preset',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((p) {
                  final isSelected = eq.preset == p;
                  return ChoiceChip(
                    label: Text(p),
                    selected: isSelected,
                    selectedColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (val) {
                      eqNotifier.setPreset(p);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LyricLine {
  final int ms;
  final String text;
  const _LyricLine(this.ms, this.text);
}
