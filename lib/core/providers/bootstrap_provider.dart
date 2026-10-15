import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/sync/sync_service.dart';
import 'package:client/core/providers/current_song_notifier.dart';

final bootstrapProvider = FutureProvider<void>((ref) async {
  final dir = await getApplicationDocumentsDirectory();

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[Echonix][Init] AudioSession configure failed: $e');
    }
  }

  // PythonBackend.init runs on priority lane
  await PythonBackend.init(dir.path);

  try {
    final sync = ref.read(syncServiceProvider.notifier);
    sync.flush();

    // Delay sync.pullIncremental() by 20 seconds after bootstrap and skip if isPlayerLoadingProvider is true (retry in 20s, max 3 times)
    void scheduleIncrementalPull(int retriesLeft) {
      Timer(const Duration(seconds: 20), () {
        final isLoading = ref.read(isPlayerLoadingProvider);
        if (isLoading) {
          if (retriesLeft > 0) {
            scheduleIncrementalPull(retriesLeft - 1);
          }
          return;
        }
        sync.pullIncremental();
      });
    }

    scheduleIncrementalPull(3);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[Echonix][Sync] Bootstrap sync initialization error: $e');
    }
  }
});
