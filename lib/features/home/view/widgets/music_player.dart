import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/providers/current_user_notifier.dart';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/utils.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/view/pages/queue_page.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

class MusicPlayer extends ConsumerStatefulWidget {
  const MusicPlayer({super.key});

  @override
  ConsumerState<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends ConsumerState<MusicPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  List<_LyricLine> _syncedLines = [];
  List<GlobalKey> _lyricKeys = [];
  String _plainLyrics = '';
  bool _hasSynced = false;
  bool _lyricsLoading = false;
  String? _lyricsLoadedFor;
  final ScrollController _lyricsScroll = ScrollController();
  int _currentLyricIndex = 0;
  Timer? _lyricTimer;
  int _lyricsOffsetMs = 0;

  Color? _dominantColor;
  String? _colorExtractedFor;

  bool _userScrolling = false;
  Timer? _userScrollEndTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
    _slideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentSong = ref.read(currentSongNotifierProvider);
      if (currentSong != null) {
        _loadLyrics(currentSong.song_name, currentSong.artist, currentSong.song_url);
        _extractDominantColor(getHighQualityThumbnail(currentSong.thumbnail_url));
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _lyricsScroll.dispose();
    _lyricTimer?.cancel();
    _userScrollEndTimer?.cancel();
    super.dispose();
  }

  void _extractDominantColor(String imageUrl) async {
    if (_colorExtractedFor == imageUrl) return;
    _colorExtractedFor = imageUrl;
    setState(() {
      _dominantColor = null; // Reset immediately on song change
    });
    try {
      final provider = NetworkImage(
        imageUrl,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'
        },
      );
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 4,
      );
      if (mounted && palette.dominantColor != null) {
        setState(() {
          _dominantColor = palette.dominantColor!.color;
        });
      }
    } catch (_) {}
  }

  void _loadLyrics(String songName, String artist, String songUrl) async {
    if (_lyricsLoadedFor == '$songName|$artist') return;
    setState(() {
      _lyricsLoading = true;
      _syncedLines = [];
      _lyricKeys = [];
      _plainLyrics = '';
      _hasSynced = false;
      _lyricsLoadedFor = '$songName|$artist';
      _lyricsOffsetMs = 0;
    });

    // Try to load offline lyrics first if song_url is a local path
    if (songUrl.startsWith('/')) {
      final metaFile = File('$songUrl.json');
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          final Map<String, dynamic> meta = jsonDecode(content);
          if (meta.containsKey('lyrics_data') && meta['lyrics_data'] != null) {
            final lyricsData = meta['lyrics_data'];
            final lyrics = lyricsData['lyrics'] as String? ?? '';
            final isSynced = lyricsData['synced'] == true;
            if (lyrics.isNotEmpty) {
              if (isSynced) {
                final lines = _parseLrc(lyrics);
                setState(() {
                  _syncedLines = lines;
                  _lyricKeys = List.generate(lines.length, (_) => GlobalKey());
                  _hasSynced = true;
                  _lyricsLoading = false;
                });
                _startLyricSync();
              } else {
                setState(() {
                  _plainLyrics = lyrics;
                  _hasSynced = false;
                  _lyricsLoading = false;
                });
              }
              return; // Offline lyrics successfully loaded!
            }
          }
        } catch (_) {}
      }
    }

    final data = await PythonBackend.getLyrics(songName, artist);
    if (!mounted) return;
    if (data['success'] == true) {
      final lyrics = data['lyrics'] as String? ?? '';
      final isSynced = data['synced'] == true;
      if (isSynced) {
        final lines = _parseLrc(lyrics);
        setState(() {
          _syncedLines = lines;
          _lyricKeys = List.generate(lines.length, (_) => GlobalKey());
          _hasSynced = true;
          _lyricsLoading = false;
        });
        _startLyricSync();
      } else {
        setState(() {
          _plainLyrics = lyrics;
          _hasSynced = false;
          _lyricsLoading = false;
        });
      }
    } else {
      setState(() => _lyricsLoading = false);
    }
  }

  List<_LyricLine> _parseLrc(String lrc) {
    final lines = <_LyricLine>[];
    final re = RegExp(r'\[(\d+):(\d+)\.(\d+)\]\s*(.*)');
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
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    } else {
      if (!_lyricsScroll.hasClients) return;
      final offset = index * 52.0 - 80;
      _lyricsScroll.animateTo(
        offset.clamp(0, _lyricsScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatOffset(int ms) {
    final sign = ms >= 0 ? '+' : '-';
    final abs = ms.abs();
    final sec = abs ~/ 1000;
    final dec = ((abs % 1000) / 100).round();
    return '$sign${sec}.${dec}s';
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongNotifierProvider);
    final songNotifier = ref.read(currentSongNotifierProvider.notifier);
    final userFavorites = ref.watch(
      currentUserNotifierProvider.select((d) => d?.favorites ?? []),
    );

    ref.listen<SongModel?>(currentSongNotifierProvider, (previous, next) {
      if (next != null) {
        _loadLyrics(next.song_name, next.artist, next.song_url);
        _extractDominantColor(getHighQualityThumbnail(next.thumbnail_url));
      }
    });

    if (currentSong == null) return const SizedBox();

    debugPrint("EchonixPlayer: song_name='${currentSong.song_name}'");
    debugPrint("EchonixPlayer: thumbnail_url='${currentSong.thumbnail_url}'");
    debugPrint("EchonixPlayer: getHighQualityThumbnail='${getHighQualityThumbnail(currentSong.thumbnail_url)}'");

    final dynColor = _dominantColor ?? hexToColor(currentSong.hex_code);

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(_slideAnimation),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              dynColor.withOpacity(0.7),
              dynColor.withOpacity(0.3),
              Colors.black,
            ],
            stops: const [0.0, 0.4, 0.85],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'NOW PLAYING',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white, size: 32),
            ),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert, color: Colors.white70),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: PageView(
                        children: [
                          Hero(
                            tag: 'music-image',
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: dynColor.withOpacity(0.4),
                                    blurRadius: 50,
                                    spreadRadius: 8,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                                image: DecorationImage(
                                  image: NetworkImage(getHighQualityThumbnail(currentSong.thumbnail_url)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          _buildLyricsView(dynColor),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
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
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    currentSong.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: IconButton(
                                key: ValueKey(userFavorites
                                    .any((f) => f.song_id == currentSong.id)),
                                onPressed: () async {
                                  await ref
                                      .read(homeViewModelProvider.notifier)
                                      .favSong(songId: currentSong.id);
                                },
                                icon: Icon(
                                  userFavorites.any(
                                          (f) => f.song_id == currentSong.id)
                                      ? CupertinoIcons.heart_fill
                                      : CupertinoIcons.heart,
                                  color: userFavorites.any(
                                          (f) => f.song_id == currentSong.id)
                                      ? Colors.redAccent
                                      : Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        StreamBuilder(
                          stream: songNotifier.audioPlayer?.positionStream,
                          builder: (context, snapshot) {
                            final position = snapshot.data ?? Duration.zero;
                            final duration =
                                songNotifier.audioPlayer?.duration ??
                                    Duration.zero;
                            final sliderVal = duration.inMilliseconds > 0
                                ? (position.inMilliseconds /
                                        duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                            return Column(
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor:
                                        Colors.white.withOpacity(0.2),
                                    thumbColor: Colors.white,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6),
                                    trackHeight: 3,
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                  ),
                                  child: Slider(
                                    value: sliderVal,
                                    min: 0,
                                    max: 1,
                                    onChanged: (_) {},
                                    onChangeEnd: songNotifier.seek,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                            color: Colors.white54, fontSize: 12),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                            color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: songNotifier.toggleShuffle,
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: ref.watch(shuffleProvider)
                                      ? Pallete.borderColor
                                      : Colors.white60,
                                  size: 24,
                                ),
                              ),
                              Consumer(
                                builder: (context, ref, _) {
                                  final mode = ref.watch(repeatModeProvider);
                                  final isActive = mode != LoopMode.off;
                                  return IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: songNotifier.cycleRepeatMode,
                                    icon: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/images/repeat.png',
                                          width: 22,
                                          height: 22,
                                          color: isActive ? Pallete.borderColor : Colors.white60,
                                        ),
                                        if (mode == LoopMode.one)
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                color: Pallete.borderColor,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Text(
                                                '1',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: songNotifier.previous,
                                icon: const Icon(Icons.skip_previous_rounded,
                                    color: Colors.white, size: 36),
                              ),
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: songNotifier.playPause,
                                  icon: ref.watch(isPlayerLoadingProvider)
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.black,
                                          ),
                                        )
                                      : Icon(
                                          ref.watch(isPlayingProvider).value ?? false
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.black,
                                          size: 36,
                                        ),
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: songNotifier.next,
                                icon: const Icon(Icons.skip_next_rounded,
                                    color: Colors.white, size: 36),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showQueue(context, songNotifier),
                                icon: const Icon(Icons.queue_music_rounded,
                                    color: Colors.white60, size: 24),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),
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

  Widget _buildLyricsView(Color accentColor) {
    if (_lyricsLoading) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasSynced && _syncedLines.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() => _lyricsOffsetMs -= 500);
                      _startLyricSync();
                    },
                    icon: const Icon(Icons.replay_5, color: Colors.white70, size: 20),
                    tooltip: 'Delay lyrics by 0.5s',
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Offset: ${_formatOffset(_lyricsOffsetMs)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _lyricsOffsetMs += 500);
                      _startLyricSync();
                    },
                    icon: const Icon(Icons.forward_5, color: Colors.white70, size: 20),
                    tooltip: 'Advance lyrics by 0.5s',
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _lyricsOffsetMs = 0);
                      _startLyricSync();
                    },
                    icon: const Icon(Icons.restart_alt, color: Colors.white38, size: 18),
                    tooltip: 'Reset offset',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  _onScrollNotification(notification);
                  return false;
                },
                child: ListView.builder(
                  controller: _lyricsScroll,
                  itemCount: _syncedLines.length,
                  padding: const EdgeInsets.only(top: 40, bottom: 40),
                itemBuilder: (context, index) {
                  final isActive = index == _currentLyricIndex;
                  return AnimatedDefaultTextStyle(
                    key: index < _lyricKeys.length ? _lyricKeys[index] : null,
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white38,
                      fontSize: isActive ? 18 : 15,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      height: 1.6,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        final notifier = ref.read(currentSongNotifierProvider.notifier);
                        final seekMs = _syncedLines[index].ms - _lyricsOffsetMs;
                        if (seekMs >= 0 && notifier.audioPlayer?.duration != null) {
                          notifier.seek(seekMs / notifier.audioPlayer!.duration!.inMilliseconds);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        child: Text(
                          _syncedLines[index].text,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    }

    if (_plainLyrics.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            _plainLyrics,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.8,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text('Swipe left for lyrics',
            style: TextStyle(color: Colors.white38)),
      ),
    );
  }

  void _showQueue(BuildContext ctx, dynamic notifier) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (context) => const QueuePage(),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _LyricLine {
  final int ms;
  final String text;
  const _LyricLine(this.ms, this.text);
}
