import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';

enum DownloadStatus { idle, queued, downloading, done, failed }

class DownloadState {
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final String? error;

  const DownloadState({
    required this.status,
    this.progress = 0.0,
    this.error,
  });
}

class DownloadsNotifier extends StateNotifier<Map<String, DownloadState>> {
  Timer? _pollTimer;

  DownloadsNotifier() : super({}) {
    _loadInitialDownloaded();
  }

  Future<void> _loadInitialDownloaded() async {
    try {
      final res = await PythonBackend.getDownloadedSongs();
      if (res['success'] == true && res['songs'] is List) {
        final Map<String, DownloadState> initial = {};
        for (final item in res['songs']) {
          if (item is Map && item['id'] != null) {
            initial[item['id'].toString()] = const DownloadState(
              status: DownloadStatus.done,
              progress: 1.0,
            );
          }
        }
        state = {...state, ...initial};
      }
    } catch (_) {}
  }

  void refreshDownloaded() {
    _loadInitialDownloaded();
  }

  void startDownloading(SongModel song) {
    state = {
      ...state,
      song.id: const DownloadState(status: DownloadStatus.queued),
    };
    PythonBackend.downloadSong(
      song.id,
      song.song_name,
      song.artist,
      song.thumbnail_url,
    );
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final res = await PythonBackend.getDownloadStatus();
        if (res['success'] == true && res['status'] is Map) {
          final Map rawStatus = res['status'] as Map;
          final updated = Map<String, DownloadState>.from(state);
          bool hasActive = false;

          rawStatus.forEach((k, v) {
            final id = k.toString();
            if (v is Map) {
              final s = v['state']?.toString();
              final prog = (v['progress'] as num?)?.toDouble() ?? 0.0;
              final err = v['error']?.toString();

              DownloadStatus status = DownloadStatus.idle;
              if (s == 'queued') {
                status = DownloadStatus.queued;
                hasActive = true;
              } else if (s == 'downloading') {
                status = DownloadStatus.downloading;
                hasActive = true;
              } else if (s == 'done') {
                status = DownloadStatus.done;
              } else if (s == 'failed') {
                status = DownloadStatus.failed;
              }

              updated[id] = DownloadState(
                status: status,
                progress: prog,
                error: err,
              );
            }
          });

          state = updated;
          if (!hasActive) {
            _pollTimer?.cancel();
            _pollTimer = null;
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final downloadsProvider = StateNotifierProvider<DownloadsNotifier, Map<String, DownloadState>>((ref) {
  return DownloadsNotifier();
});

class DownloadButton extends ConsumerWidget {
  final SongModel song;
  final double size;
  final Color? color;

  const DownloadButton({
    super.key,
    required this.song,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final dlState = downloads[song.id] ?? const DownloadState(status: DownloadStatus.idle);
    final themeColor = color ?? Theme.of(context).colorScheme.primary;

    switch (dlState.status) {
      case DownloadStatus.queued:
        return SizedBox(
          width: size,
          height: size,
          child: const Padding(
            padding: EdgeInsets.all(4.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case DownloadStatus.downloading:
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: dlState.progress > 0 ? dlState.progress : null,
                strokeWidth: 2.5,
                color: themeColor,
              ),
              if (dlState.progress > 0)
                Text(
                  '${(dlState.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: (size * 0.35).clamp(8.0, 11.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        );
      case DownloadStatus.done:
        return Icon(
          Icons.check_circle_rounded,
          size: size,
          color: Theme.of(context).colorScheme.tertiary,
        );
      case DownloadStatus.failed:
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          icon: Icon(
            Icons.error_outline_rounded,
            size: size,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: dlState.error ?? 'Download failed. Tap to retry.',
          onPressed: () {
            ref.read(downloadsProvider.notifier).startDownloading(song);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download queued')),
            );
          },
        );
      case DownloadStatus.idle:
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          icon: Icon(
            Icons.download_rounded,
            size: size,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Download',
          onPressed: () {
            ref.read(downloadsProvider.notifier).startDownloading(song);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download queued')),
            );
          },
        );
    }
  }
}
