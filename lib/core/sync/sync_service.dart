import 'dart:async';
import 'package:client/core/python_backend.dart';
import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/viewmodel/likes_notifier.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class SyncItem {
  final String id;
  final String type; // rate, history, playlist_create, playlist_rename, playlist_delete, playlist_add, playlist_remove
  final Map<String, dynamic> payload;
  final int createdAt;
  final int attempts;
  final int? nextRetryAt;

  SyncItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.nextRetryAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt,
        'attempts': attempts,
        'nextRetryAt': nextRetryAt,
      };

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: (map['nextRetryAt'] as num?)?.toInt(),
    );
  }

  SyncItem copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    int? createdAt,
    int? attempts,
    int? nextRetryAt,
  }) {
    return SyncItem(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }
}

class SyncState {
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncTime;
  final bool isSyncing;
  final bool reconnectNeeded;

  SyncState({
    required this.pendingCount,
    required this.failedCount,
    this.lastSyncTime,
    this.isSyncing = false,
    this.reconnectNeeded = false,
  });

  SyncState copyWith({
    int? pendingCount,
    int? failedCount,
    DateTime? lastSyncTime,
    bool? isSyncing,
    bool? reconnectNeeded,
  }) {
    return SyncState(
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      isSyncing: isSyncing ?? this.isSyncing,
      reconnectNeeded: reconnectNeeded ?? this.reconnectNeeded,
    );
  }
}

class SyncService extends StateNotifier<SyncState> with WidgetsBindingObserver {
  final Ref _ref;
  Timer? _debounceTimer;
  StreamSubscription? _connectivitySub;
  bool _isFlushing = false;

  SyncService(this._ref)
      : super(SyncState(
          pendingCount: 0,
          failedCount: 0,
        )) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  void _init() {
    _refreshCounts();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        flush();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      flush();
      pullIncremental();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  Box get _box => Hive.box();

  void _refreshCounts() {
    final rawOutbox = _box.get('sync_outbox');
    final rawFailed = _box.get('sync_failed');
    final lastSyncMs = _box.get('last_sync_time') as num?;

    final outboxCount = rawOutbox is List ? rawOutbox.length : 0;
    final failedCount = rawFailed is List ? rawFailed.length : 0;

    state = state.copyWith(
      pendingCount: outboxCount,
      failedCount: failedCount,
      lastSyncTime: lastSyncMs != null ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs.toInt()) : null,
    );
  }

  List<SyncItem> _loadOutbox() {
    final raw = _box.get('sync_outbox');
    if (raw is List) {
      return raw.map((e) => SyncItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
    return [];
  }

  void _saveOutbox(List<SyncItem> items) {
    _box.put('sync_outbox', items.map((e) => e.toMap()).toList());
    _refreshCounts();
  }

  List<SyncItem> _loadFailed() {
    final raw = _box.get('sync_failed');
    if (raw is List) {
      return raw.map((e) => SyncItem.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
    return [];
  }

  void _saveFailed(List<SyncItem> items) {
    _box.put('sync_failed', items.map((e) => e.toMap()).toList());
    _refreshCounts();
  }

  // ---------------------------------------------------------------------------
  // Enqueue
  // ---------------------------------------------------------------------------

  void enqueue(String type, Map<String, dynamic> payload) {
    final item = SyncItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${type}',
      type: type,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final outbox = _loadOutbox();
    outbox.add(item);
    _saveOutbox(outbox);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 10), () => flush());
  }

  // ---------------------------------------------------------------------------
  // Coalescing
  // ---------------------------------------------------------------------------

  List<SyncItem> _coalesce(List<SyncItem> ops) {
    if (ops.isEmpty) return [];

    final List<SyncItem> result = [];

    // 1. Coalesce 'rate' ops
    final Map<String, List<SyncItem>> ratesByVideo = {};
    for (final op in ops) {
      if (op.type == 'rate') {
        final vid = op.payload['videoId']?.toString() ?? '';
        ratesByVideo.putIfAbsent(vid, () => []).add(op);
      }
    }

    final Set<String> ratesToKeepIds = {};
    for (final entry in ratesByVideo.entries) {
      final list = entry.value;
      if (list.length >= 2) {
        final firstRating = list.first.payload['rating'];
        final lastRating = list.last.payload['rating'];
        if (firstRating == 'LIKE' && lastRating == 'INDIFFERENT') {
          continue; // Cancelled
        }
      }
      ratesToKeepIds.add(list.last.id);
    }

    // 2. Coalesce 'history' ops (drop duplicate videoId within 30 min)
    final Map<String, int> lastHistoryTime = {};
    final Set<String> historyToKeepIds = {};
    for (final op in ops) {
      if (op.type == 'history') {
        final vid = op.payload['videoId']?.toString() ?? '';
        final t = op.createdAt;
        if (!lastHistoryTime.containsKey(vid) || (t - lastHistoryTime[vid]! > 1800000)) {
          historyToKeepIds.add(op.id);
          lastHistoryTime[vid] = t;
        }
      }
    }

    // 3. Coalesce 'playlist_add' ops (merge into single call)
    final Map<String, List<String>> mergedAdds = {};
    final Map<String, SyncItem> firstAddOp = {};

    for (final op in ops) {
      if (op.type == 'rate') {
        if (ratesToKeepIds.contains(op.id)) {
          result.add(op);
        }
      } else if (op.type == 'history') {
        if (historyToKeepIds.contains(op.id)) {
          result.add(op);
        }
      } else if (op.type == 'playlist_add') {
        final target = op.payload['playlistId'] ?? op.payload['localId'] ?? '';
        final List vids = op.payload['videoIds'] as List? ?? [];
        final list = mergedAdds.putIfAbsent(target.toString(), () => []);
        for (final v in vids) {
          if (!list.contains(v.toString())) list.add(v.toString());
        }
        firstAddOp.putIfAbsent(target.toString(), () => op);
      } else {
        result.add(op);
      }
    }

    for (final entry in mergedAdds.entries) {
      final baseOp = firstAddOp[entry.key]!;
      final newPayload = Map<String, dynamic>.from(baseOp.payload);
      newPayload['videoIds'] = entry.value;
      result.add(SyncItem(
        id: baseOp.id,
        type: 'playlist_add',
        payload: newPayload,
        createdAt: baseOp.createdAt,
        attempts: baseOp.attempts,
        nextRetryAt: baseOp.nextRetryAt,
      ));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Flush
  // ---------------------------------------------------------------------------

  Future<void> flush() async {
    if (_isFlushing) return;
    _isFlushing = true;
    state = state.copyWith(isSyncing: true);

    try {
      final authStatus = await PythonBackend.checkAuthStatus();
      if (authStatus['authenticated'] != true) {
        // Not authenticated: ops stay queued
        return;
      }
      if (authStatus['valid'] == false) {
        state = state.copyWith(reconnectNeeded: true);
        return;
      }

      state = state.copyWith(reconnectNeeded: false);

      final rawOutbox = _loadOutbox();
      if (rawOutbox.isEmpty) return;

      final coalesced = _coalesce(rawOutbox);
      final remaining = <SyncItem>[];
      final failedList = _loadFailed();
      final now = DateTime.now().millisecondsSinceEpoch;

      final backoffSeconds = [30, 120, 600, 3600, 3600, 3600, 3600, 3600];

      for (int i = 0; i < coalesced.length; i++) {
        var op = coalesced[i];

        if (op.nextRetryAt != null && op.nextRetryAt! > now) {
          remaining.add(op);
          continue;
        }

        final res = await _executeOp(op);
        final status = res['http_status'];

        if (res['success'] == true) {
          debugPrint('[Echonix][sync] op=${op.type} ok status=200');

          if (op.type == 'playlist_create' && res['playlistId'] != null) {
            final remoteId = res['playlistId'].toString();
            final localId = op.payload['localId']?.toString();
            if (localId != null) {
              await _ref.read(localPlaylistsProvider.notifier).updatePlaylistDetails(
                    localId,
                    remoteId: remoteId,
                  );
              // Update subsequent ops referencing this localId
              for (int j = i + 1; j < coalesced.length; j++) {
                if (coalesced[j].payload['localId'] == localId) {
                  coalesced[j].payload['playlistId'] = remoteId;
                }
              }
            }
          }
        } else {
          debugPrint('[Echonix][sync] op=${op.type} fail status=$status error=${res['error']}');

          if (status == 401 || status == 403) {
            state = state.copyWith(reconnectNeeded: true);
            remaining.add(op);
            // Append the rest of the un-executed ops
            for (int k = i + 1; k < coalesced.length; k++) {
              remaining.add(coalesced[k]);
            }
            break;
          }

          final attempts = op.attempts + 1;
          if (attempts >= 8) {
            failedList.add(op.copyWith(attempts: attempts));
          } else {
            final delaySec = backoffSeconds[(attempts - 1).clamp(0, backoffSeconds.length - 1)];
            final nextRetry = DateTime.now().millisecondsSinceEpoch + (delaySec * 1000);
            remaining.add(op.copyWith(attempts: attempts, nextRetryAt: nextRetry));
          }
        }
      }

      _saveOutbox(remaining);
      _saveFailed(failedList);

      final syncTime = DateTime.now();
      _box.put('last_sync_time', syncTime.millisecondsSinceEpoch);
      state = state.copyWith(lastSyncTime: syncTime);
    } catch (e) {
      debugPrint('[Echonix][sync] flush error: $e');
    } finally {
      _isFlushing = false;
      state = state.copyWith(isSyncing: false);
      _refreshCounts();
    }
  }

  Future<Map<String, dynamic>> _executeOp(SyncItem op) async {
    switch (op.type) {
      case 'rate':
        final videoId = op.payload['videoId']?.toString() ?? '';
        final rating = op.payload['rating']?.toString() ?? 'INDIFFERENT';
        return PythonBackend.rateSong(videoId, rating);

      case 'history':
        final videoId = op.payload['videoId']?.toString() ?? '';
        await PythonBackend.addHistory(videoId);
        return {'success': true};

      case 'playlist_create':
        final title = op.payload['title']?.toString() ?? '';
        final description = op.payload['description']?.toString() ?? '';
        final videoIds = List<String>.from(op.payload['videoIds'] as List? ?? []);
        return PythonBackend.createPlaylist(title, description: description, videoIds: videoIds);

      case 'playlist_rename':
        final playlistId = op.payload['playlistId']?.toString() ?? '';
        final title = op.payload['title']?.toString() ?? '';
        if (playlistId.isEmpty) return {'success': false, 'error': 'Missing playlistId'};
        return PythonBackend.renamePlaylist(playlistId, title);

      case 'playlist_delete':
        final playlistId = op.payload['playlistId']?.toString() ?? '';
        if (playlistId.isEmpty) return {'success': false, 'error': 'Missing playlistId'};
        return PythonBackend.deletePlaylist(playlistId);

      case 'playlist_add':
        final playlistId = op.payload['playlistId']?.toString() ?? '';
        final videoIds = List<String>.from(op.payload['videoIds'] as List? ?? []);
        if (playlistId.isEmpty) return {'success': false, 'error': 'Missing playlistId'};
        return PythonBackend.addPlaylistItems(playlistId, videoIds);

      case 'playlist_remove':
        final playlistId = op.payload['playlistId']?.toString() ?? '';
        final rawItems = op.payload['items'] as List? ?? [];
        final items = List<Map<String, String>>.from(
          rawItems.map((x) => Map<String, String>.from(x as Map)),
        );
        if (playlistId.isEmpty) return {'success': false, 'error': 'Missing playlistId'};
        return PythonBackend.removePlaylistItems(playlistId, items);

      default:
        return {'success': false, 'error': 'Unknown op type: ${op.type}'};
    }
  }

  // ---------------------------------------------------------------------------
  // Failed ops management
  // ---------------------------------------------------------------------------

  void retryFailed() {
    final failed = _loadFailed();
    final outbox = _loadOutbox();

    final retrying = failed.map((e) => e.copyWith(attempts: 0, nextRetryAt: null)).toList();
    outbox.addAll(retrying);
    _saveOutbox(outbox);
    _saveFailed([]);
    flush();
  }

  void discardFailed() {
    _saveFailed([]);
  }

  // ---------------------------------------------------------------------------
  // Incremental pull (P3-T3)
  // ---------------------------------------------------------------------------

  Future<void> pullIncremental({bool force = false}) async {
    try {
      final auth = await PythonBackend.checkAuthStatus();
      if (auth['authenticated'] != true || auth['valid'] == false) return;

      final lastPullMs = _box.get('last_pull_time') as num?;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && lastPullMs != null && (now - lastPullMs < 1800000)) {
        // Less than 30 minutes
        return;
      }

      // 1. Pull liked songs
      final favRes = await PythonBackend.getLikedSongs(limit: 500);
      if (favRes['success'] == true && favRes['songs'] is List) {
        final List songsRaw = favRes['songs'] as List;
        final remoteSongs = songsRaw
            .whereType<Map>()
            .map((m) => SongModel.fromBackend(Map<String, dynamic>.from(m), hexCode: 'B388FF'))
            .where((s) => s.id.isNotEmpty)
            .toList();

        // Pending rate ops
        final outbox = _loadOutbox();
        final pendingLikeIds = <String>{};
        final pendingUnlikeIds = <String>{};
        for (final op in outbox) {
          if (op.type == 'rate') {
            final vid = op.payload['videoId']?.toString() ?? '';
            final rating = op.payload['rating']?.toString();
            if (rating == 'LIKE') {
              pendingLikeIds.add(vid);
              pendingUnlikeIds.remove(vid);
            } else if (rating == 'INDIFFERENT' || rating == 'DISLIKE') {
              pendingUnlikeIds.add(vid);
              pendingLikeIds.remove(vid);
            }
          }
        }

        final Set<String> mergedIds = remoteSongs
            .map((s) => s.id)
            .where((id) => !pendingUnlikeIds.contains(id))
            .toSet();
        mergedIds.addAll(pendingLikeIds);

        // Update liked ids box and notifier
        _ref.read(likedSongIdsProvider.notifier).syncRemoteIds(mergedIds, remoteSongs);
      }

      // 2. Pull library playlists
      final plRes = await PythonBackend.getLibraryPlaylists(limit: 50);
      if (plRes['success'] == true && plRes['playlists'] is List) {
        final List playlistsRaw = plRes['playlists'] as List;
        _box.put('library_playlists_cache', {
          'savedAt': now,
          'playlists': playlistsRaw,
        });

        final localPlaylists = _ref.read(localPlaylistsProvider);
        for (final p in playlistsRaw) {
          if (p is! Map) continue;
          final remoteId = p['id']?.toString() ?? '';
          final title = p['title']?.toString() ?? '';
          if (remoteId.isEmpty) continue;

          final exists = localPlaylists.any((lp) => lp.remoteId == remoteId);
          if (!exists) {
            // Check if match by name without remoteId
            final matchName = localPlaylists.where((lp) => lp.remoteId == null && lp.name.toLowerCase() == title.toLowerCase()).firstOrNull;
            if (matchName != null) {
              await _ref.read(localPlaylistsProvider.notifier).updatePlaylistDetails(
                    matchName.id,
                    remoteId: remoteId,
                  );
            } else {
              await _ref.read(localPlaylistsProvider.notifier).createPlaylist(
                    title,
                    remoteId: remoteId,
                  );
            }
          }
        }
      }

      _box.put('last_pull_time', now);
    } catch (e) {
      debugPrint('[Echonix][sync] pullIncremental error: $e');
    }
  }
}

final syncServiceProvider = StateNotifierProvider<SyncService, SyncState>((ref) {
  return SyncService(ref);
});
