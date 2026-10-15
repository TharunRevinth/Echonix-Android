import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/theme/echonix_theme.dart';
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

    try {
      final res = await PythonBackend.getLyrics(
        song.song_name,
        song.artist,
        durationSeconds: song.duration_seconds,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final synced = res['synced'] == true;
        final lyrics = res['lyrics'] as String? ?? '';
        if (lyrics.isNotEmpty) {
          cache[songId] = {'synced': synced, 'lyrics': lyrics};
          while (cache.length > 100) {
            final oldestKey = cache.keys.first;
            cache.remove(oldestKey);
          }
          box.put('lyrics_cache', cache);
          _applyLyrics(lyrics, synced, songId);
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _lyricsLoading = false;
        _syncedLines = [];
        _plainLyrics = 'No lyrics found';
      });
    }
  }

  List<_LyricLine> _parseLrc(String lrc) {
    final lines = <_LyricLine>[];
    final regExp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');
    for (final rawLine in lrc.split('\n')) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final m = int.parse(match.group(1)!);
        final s = double.parse(match.group(2)!);
        final text = match.group(3)!.trim();
        final ms = (m * 60 * 1000 + s * 1000).round();
        if (text.isNotEmpty) {
          lines.add(_LyricLine(ms, text));
        }
      }
    }
    lines.sort((a, b) => a.ms.compareTo(b.ms));
    return lines;
  }

  void _startLyricSync() {
    _lyricTimer?.cancel();
    _lyricTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted || _syncedLines.isEmpty || _userScrolling) return;

      final player = ref.read(currentSongNotifierProvider.notifier).audioPlayer;
      if (player == null) return;

      final posMs = player.position.inMilliseconds + _lyricsOffsetMs;
      int activeIndex = 0;
      for (int i = 0; i < _syncedLines.length; i++) {
        if (_syncedLines[i].ms <= posMs) {
          activeIndex = i;
        } else {
          break;
        }
      }

      if (activeIndex != _currentLyricIndex) {
        setState(() {
          _currentLyricIndex = activeIndex;
        });
        _scrollToActiveLyric(activeIndex);
      }
    });
  }

  void _scrollToActiveLyric(int index) {
    if (_userScrolling) return;
    if (index >= 0 && index < _lyricKeys.length) {
      final keyContext = _lyricKeys[index].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 300),
          curve: Easing.emphasizedDecelerate,
          alignment: 0.4,
        );
      }
    }
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _userScrolling = true;
        _userScrollEndTimer?.cancel();
      }
    } else if (notification is ScrollEndNotification) {
      _userScrollEndTimer?.cancel();
      _userScrollEndTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _userScrolling = false;
          });
          _scrollToActiveLyric(_currentLyricIndex);
        }
      });
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatOffset(int ms) {
    if (ms == 0) return '0.0s';
    final sign = ms > 0 ? '+' : '';
    return '$sign${(ms / 1000.0).toStringAsFixed(1)}s';
  }

  void _openQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const FractionallySizedBox(
          heightFactor: 0.70,
          child: QueuePage(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongNotifierProvider);
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);

    ref.listen(currentSongNotifierProvider, (prev, next) {
      if (next != null && (prev == null || prev.id != next.id)) {
        _loadLyrics(next);
      }
    });

    if (currentSong == null) return const SizedBox.shrink();

    final hqThumbnail = getHighQualityThumbnail(currentSong.thumbnail_url);
    final isLiked = ref.watch(likedSongIdsProvider).contains(currentSong.id);
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final playerScheme = ref.watch(playerSchemeProvider(hqThumbnail));
    final textTheme = Theme.of(context).textTheme;

    return Theme(
      data: Theme.of(context).copyWith(colorScheme: playerScheme),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;

          return GestureDetector(
            onVerticalDragUpdate: (details) {
              widget.onVerticalDragUpdate?.call(details.primaryDelta ?? 0.0);
            },
            onVerticalDragEnd: (details) {
              widget.onVerticalDragEnd?.call(details.primaryVelocity ?? 0.0);
            },
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: scheme.surface,
                end: scheme.primary.withValues(alpha: 0.35),
              ),
              duration: const Duration(milliseconds: 400),
              curve: Easing.emphasizedDecelerate,
              builder: (context, primaryTint, child) {
                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        primaryTint ?? scheme.surface,
                        scheme.surface,
                      ],
                      stops: const [0.0, 0.55],
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
                            // 1. Top Bar: Grab Handle & Playing from line
                            GestureDetector(
                              onTap: widget.onClose ?? () => Navigator.maybePop(context),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.only(top: 10, bottom: 6),
                                alignment: Alignment.center,
                                child: Container(
                                  width: 38,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  onPressed: widget.onClose ?? () => Navigator.maybePop(context),
                                  icon: Icon(Icons.keyboard_arrow_down, color: scheme.onSurface, size: 28),
                                ),
                                Text(
                                  'Playing from Library',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                                  color: scheme.surfaceContainerHigh,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  onSelected: (val) {
                                    if (val == 'queue') {
                                      _openQueueSheet(context);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'queue',
                                      child: Text('View Queue', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                                    ),
                                    PopupMenuItem(
                                      enabled: false,
                                      child: Text(
                                        'Album: ${currentSong.album ?? 'Single'}',
                                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // 2. Artwork & Lyrics cross-fade area
                            Expanded(
                              child: Center(
                                child: AnimatedCrossFade(
                                  duration: const Duration(milliseconds: 300),
                                  firstCurve: Easing.emphasizedDecelerate,
                                  secondCurve: Easing.emphasizedDecelerate,
                                  crossFadeState: _showLyrics
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                  firstChild: _buildArtworkView(context, hqThumbnail, scheme, isPlaying),
                                  secondChild: _buildLyricsView(context, scheme, textTheme),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 3. Title, Artist, Like Heart, Download Button
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
                                        style: textTheme.headlineSmall?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentSong.album != null && currentSong.album!.isNotEmpty
                                            ? '${currentSong.artist} • ${currentSong.album}'
                                            : currentSong.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton.filledTonal(
                                  style: IconButton.styleFrom(
                                    backgroundColor: scheme.surfaceContainerHighest,
                                    foregroundColor: isLiked ? scheme.tertiary : scheme.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    ref.read(likedSongIdsProvider.notifier).toggle(currentSong);
                                  },
                                  icon: Icon(
                                    isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                                    color: isLiked ? scheme.tertiary : scheme.onSurfaceVariant,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DownloadButton(
                                  song: currentSong,
                                  size: 24,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // 4. Progress bar with dedicated StreamBuilder
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
                                        trackHeight: 4.0,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                        activeTrackColor: scheme.primary,
                                        inactiveTrackColor: scheme.outlineVariant,
                                        thumbColor: scheme.primary,
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
                                            style: textTheme.labelSmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(totalDuration),
                                            style: textTheme.labelSmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
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

                            // 5. Transport Row: shuffle, previous, play/pause (72dp primaryContainer), next, repeat
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  onPressed: songNotifier.toggleShuffle,
                                  icon: Icon(
                                    CupertinoIcons.shuffle,
                                    color: ref.watch(shuffleProvider)
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                                    size: 22,
                                  ),
                                ),
                                IconButton(
                                  onPressed: songNotifier.previous,
                                  icon: Icon(
                                    CupertinoIcons.backward_fill,
                                    color: scheme.onSurface,
                                    size: 32,
                                  ),
                                ),
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: scheme.primaryContainer,
                                    boxShadow: [
                                      BoxShadow(
                                        color: scheme.scrim.withValues(alpha: 0.3),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: songNotifier.playPause,
                                    icon: ref.watch(isPlayerLoadingProvider)
                                        ? SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: scheme.onPrimaryContainer,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying
                                                ? CupertinoIcons.pause_fill
                                                : CupertinoIcons.play_fill,
                                            color: scheme.onPrimaryContainer,
                                            size: 34,
                                          ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: songNotifier.next,
                                  icon: Icon(
                                    CupertinoIcons.forward_fill,
                                    color: scheme.onSurface,
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
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // 6. Bottom Row: lyrics, queue, sleep timer, equalizer
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: _showLyrics
                                          ? scheme.primaryContainer
                                          : scheme.surfaceContainerHigh,
                                      foregroundColor: _showLyrics
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showLyrics = !_showLyrics;
                                      });
                                    },
                                    icon: const Icon(Icons.lyrics_outlined, size: 24),
                                  ),
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: scheme.surfaceContainerHigh,
                                      foregroundColor: scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () => _openQueueSheet(context),
                                    icon: const Icon(Icons.queue_music_rounded, size: 24),
                                  ),
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: ref.watch(sleepTimerProvider) != null
                                          ? scheme.primaryContainer
                                          : scheme.surfaceContainerHigh,
                                      foregroundColor: ref.watch(sleepTimerProvider) != null
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () => _showSleepTimerDialog(context, scheme, textTheme),
                                    icon: Icon(
                                      ref.watch(sleepTimerProvider) != null
                                          ? Icons.bedtime_rounded
                                          : Icons.bedtime_outlined,
                                      size: 24,
                                    ),
                                  ),
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: scheme.surfaceContainerHigh,
                                      foregroundColor: scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () => _showEqualizerDialog(context, scheme, textTheme),
                                    icon: const Icon(Icons.tune_rounded, size: 24),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtworkView(BuildContext context, String hqThumbnail, ColorScheme scheme, bool isPlaying) {
    final screenWidth = MediaQuery.of(context).size.width;
    final size = screenWidth * 0.82;

    return Center(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showLyrics = true;
          });
        },
        child: AnimatedScale(
          scale: isPlaying ? 1.0 : 0.92,
          duration: const Duration(milliseconds: 200),
          curve: Easing.emphasizedDecelerate,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: hqThumbnail,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: scheme.surfaceContainerHigh,
                    child: Icon(Icons.music_note, color: scheme.onSurfaceVariant, size: 64),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context, ColorScheme scheme, TextTheme textTheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final size = screenWidth * 0.82;

    return Container(
      width: size,
      height: size + 40,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lyrics',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  PopupMenuButton<int>(
                    icon: Icon(
                      Icons.tune,
                      color: _lyricsOffsetMs != 0 ? scheme.primary : scheme.onSurfaceVariant,
                      size: 20,
                    ),
                    color: scheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: -500,
                        child: Text('-0.5s Earlier', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                      ),
                      PopupMenuItem(
                        value: 500,
                        child: Text('+0.5s Later', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                      ),
                      PopupMenuItem(
                        value: 0,
                        child: Text('Reset', style: textTheme.bodyMedium?.copyWith(color: scheme.error)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: scheme.onSurfaceVariant, size: 20),
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
                ? Center(child: CircularProgressIndicator(color: scheme.primary))
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

                            return RepaintBoundary(
                              child: GestureDetector(
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
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Easing.emphasizedDecelerate,
                                    opacity: isActive ? 1.0 : (distance <= 2 ? 0.50 : 0.25),
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      curve: Easing.emphasizedDecelerate,
                                      textAlign: TextAlign.center,
                                      style: (isActive ? textTheme.titleLarge : textTheme.titleMedium)?.copyWith(
                                            color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
                                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                            height: 1.6,
                                          ) ??
                                          TextStyle(
                                            color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
                                          ),
                                      child: Text(line.text),
                                    ),
                                  ),
                                ),
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
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.8,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showSleepTimerDialog(BuildContext context, ColorScheme scheme, TextTheme textTheme) {
    final timerNotifier = ref.read(sleepTimerProvider.notifier);
    final endsAt = ref.read(sleepTimerProvider);
    final hasTimer = endsAt != null && endsAt.isAfter(DateTime.now());
    final remainingMinutes = hasTimer ? endsAt.difference(DateTime.now()).inMinutes + 1 : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasTimer ? 'Sleep Timer Active (${remainingMinutes}m left)' : 'Set Sleep Timer',
                style: textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (hasTimer)
                ListTile(
                  leading: Icon(Icons.timer_off_outlined, color: scheme.error),
                  title: Text('Cancel Timer', style: textTheme.titleMedium?.copyWith(color: scheme.error)),
                  onTap: () {
                    timerNotifier.stopTimer();
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                title: Text('15 Minutes', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                onTap: () {
                  timerNotifier.setTimer(15);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('30 Minutes', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                onTap: () {
                  timerNotifier.setTimer(30);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('45 Minutes', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
                onTap: () {
                  timerNotifier.setTimer(45);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('60 Minutes', style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
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

  void _showEqualizerDialog(BuildContext context, ColorScheme scheme, TextTheme textTheme) {
    final eq = ref.watch(equalizerProvider);
    final eqNotifier = ref.read(equalizerProvider.notifier);

    final presets = ['Normal', 'Bass Boost', 'Pop', 'Rock', 'Classical', 'Jazz', 'Custom'];

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Equalizer Preset',
                style: textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
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
                    selectedColor: scheme.primaryContainer,
                    backgroundColor: scheme.surfaceContainerHighest,
                    labelStyle: textTheme.labelLarge?.copyWith(
                      color: isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
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
