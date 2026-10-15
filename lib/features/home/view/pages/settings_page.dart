import 'package:client/core/theme/echonix_theme.dart';
import 'package:client/core/theme/glass.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/sync/sync_service.dart';
import 'package:client/features/home/repositories/home_local_repository.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
import 'package:client/core/widgets/stream_diagnostics_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _cookieController = TextEditingController();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _isConnecting = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    final status = await PythonBackend.checkAuthStatus();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = status['authenticated'] ?? false;
      _isLoading = false;
    });
  }

  void _saveCredentials() async {
    final input = _cookieController.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isConnecting = true;
      _message = 'Verifying and connecting to YouTube Music...';
    });

    final dir = await getApplicationDocumentsDirectory();
    final res = await PythonBackend.loginWithCookie(input, dir.path);
    if (!mounted) return;
    if (res['success'] == true) {
      ref.invalidate(isYTMConnectedProvider);
      ref.invalidate(getHomeFeedSectionsProvider);
      ref.read(syncServiceProvider.notifier).flush();
      ref.read(syncServiceProvider.notifier).pullIncremental(force: true);
      setState(() {
        _isAuthenticated = true;
        _isConnecting = false;
        _message = 'Connected successfully!';
        _cookieController.clear();
      });
    } else {
      setState(() {
        _isConnecting = false;
        _message = 'Connection failed: ${res['error'] ?? 'Invalid cookie.'}';
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _logout() async {
    setState(() {
      _isLoading = true;
    });
    await PythonBackend.logout();
    ref.invalidate(isYTMConnectedProvider);
    ref.invalidate(getHomeFeedSectionsProvider);
    setState(() {
      _isAuthenticated = false;
      _isLoading = false;
      _message = 'Logged out successfully.';
    });
  }

  String _formatRemainingTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSavePresetDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Save Custom EQ'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter preset name...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  ref.read(equalizerProvider.notifier).saveCustomPreset(name);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved custom preset "$name"')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 20),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final dockHeight = ref.watch(dockHeightProvider);

    final eqSettings = ref.watch(equalizerProvider);
    final sleepEndsAt = ref.watch(sleepTimerProvider);
    final remainingSleep = sleepEndsAt != null
        ? sleepEndsAt.difference(DateTime.now()).inSeconds.clamp(0, 86400)
        : 0;
    final syncState = ref.watch(syncServiceProvider);
    final effectsMode = ref.watch(visualEffectsModeProvider);

    final List<String> dropdownItems = [
      'Normal',
      'Bass Boost',
      'Pop',
      'Rock',
      'Classical',
      'Jazz',
      'Custom',
      ...eqSettings.customPresets.keys,
    ];

    final int bandsCount = eqSettings.frequencies.length;
    List<double> rawGains = [];
    if (eqSettings.preset == 'Custom') {
      rawGains = eqSettings.customGains;
    } else if (eqSettings.customPresets.containsKey(eqSettings.preset)) {
      rawGains = eqSettings.customPresets[eqSettings.preset]!;
    } else {
      switch (eqSettings.preset) {
        case 'Normal':
          rawGains = List.filled(bandsCount, 0.0);
          break;
        case 'Bass Boost':
          rawGains = List.generate(bandsCount, (i) => i < 2 ? (5.0 - i * 2.0) : 0.0);
          break;
        case 'Pop':
          rawGains = List.generate(bandsCount, (i) => [1.0, 2.0, 3.0, 1.0, -1.0][i % 5]);
          break;
        case 'Rock':
          rawGains = List.generate(bandsCount, (i) => [3.0, 1.0, -2.0, 2.0, 4.0][i % 5]);
          break;
        case 'Classical':
          rawGains = List.generate(bandsCount, (i) => [4.0, 2.0, 0.0, 2.0, 3.0][i % 5]);
          break;
        case 'Jazz':
          rawGains = List.generate(bandsCount, (i) => [3.0, 2.0, -1.0, 2.0, 1.0][i % 5]);
          break;
        default:
          rawGains = List.filled(bandsCount, 0.0);
          break;
      }
    }

    final List<double> currentGains = List.generate(
      bandsCount,
      (i) => i < rawGains.length ? rawGains[i] : 0.0,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Account and sync
                  _buildSectionHeader(context, 'Account & Sync'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (syncState.reconnectNeeded) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorScheme.error),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Reconnect needed: Your YouTube Music session has expired or requires re-authentication.',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_isAuthenticated) ...[
                            Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Connected to YouTube Music',
                                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Personalized library and history are synchronized.',
                                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton.tonal(
                              onPressed: _logout,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 40),
                              ),
                              child: const Text('Disconnect Account'),
                            ),
                          ] else ...[
                            Text(
                              'Connect YouTube Music Account',
                              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Paste your cookie or cURL command below to access your account.',
                              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _cookieController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Paste cookie string or cURL command here...',
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _isConnecting ? null : _saveCredentials,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              child: _isConnecting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Connect Account'),
                            ),
                            if (_message.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _message,
                                style: textTheme.bodySmall?.copyWith(
                                  color: _message.contains('success') || _message.contains('Connected')
                                      ? colorScheme.primary
                                      : colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                          const Divider(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Last sync',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              Text(
                                syncState.lastSyncTime != null ? _formatDateTime(syncState.lastSyncTime!) : 'Never',
                                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pending changes',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              Text(
                                '${syncState.pendingCount}',
                                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (syncState.failedCount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Failed operations',
                                  style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
                                ),
                                Text(
                                  '${syncState.failedCount}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: syncState.isSyncing
                                      ? null
                                      : () {
                                          ref.read(syncServiceProvider.notifier).flush();
                                          ref.read(syncServiceProvider.notifier).pullIncremental(force: true);
                                        },
                                  icon: syncState.isSyncing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text('Sync Now'),
                                ),
                              ),
                              if (syncState.failedCount > 0) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => ref.read(syncServiceProvider.notifier).retryFailed(),
                                  child: const Text('Retry'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => ref.read(syncServiceProvider.notifier).discardFailed(),
                                  child: const Text('Discard'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Playback
                  _buildSectionHeader(context, 'Playback'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text('Queue Autoplay Prediction'),
                          subtitle: const Text('Continues playback with predicted similar tracks'),
                          value: ref.watch(autoplayEnabledProvider),
                          onChanged: (_) {
                            ref.read(autoplayEnabledProvider.notifier).toggle();
                          },
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.bedtime_outlined, color: colorScheme.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Bedtime Mode (Sleep Timer)',
                                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  if (remainingSleep > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _formatRemainingTime(remainingSleep),
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Automatically pauses playback when the timer finishes.',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildSleepChip(0, 'Off', remainingSleep),
                                  _buildSleepChip(5, '5 min', remainingSleep),
                                  _buildSleepChip(10, '10 min', remainingSleep),
                                  _buildSleepChip(15, '15 min', remainingSleep),
                                  _buildSleepChip(30, '30 min', remainingSleep),
                                  _buildSleepChip(45, '45 min', remainingSleep),
                                  _buildSleepChip(60, '1 hour', remainingSleep),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Audio & Equalizer
                  _buildSectionHeader(context, 'Audio & Equalizer'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Hardware Equalizer'),
                            subtitle: const Text('Custom frequency bands and audio enhancements'),
                            value: eqSettings.enabled,
                            onChanged: (val) {
                              ref.read(equalizerProvider.notifier).toggle(val);
                            },
                          ),
                          if (eqSettings.enabled) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Interactive Curve Control (Drag to adjust)',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            EqCurveWidget(
                              colorScheme: colorScheme,
                              gains: currentGains,
                              frequencies: eqSettings.frequencies,
                              onBandChanged: (bandIdx, gain) {
                                ref.read(equalizerProvider.notifier).setBand(bandIdx, gain);
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Preset Mode',
                                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Row(
                                  children: [
                                    DropdownButton<String>(
                                      value: dropdownItems.contains(eqSettings.preset) ? eqSettings.preset : 'Normal',
                                      dropdownColor: colorScheme.surfaceContainerHigh,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      underline: const SizedBox(),
                                      items: dropdownItems.map((String val) {
                                        return DropdownMenuItem<String>(
                                          value: val,
                                          child: Text(val),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          ref.read(equalizerProvider.notifier).setPreset(val);
                                        }
                                      },
                                    ),
                                    if (eqSettings.customPresets.containsKey(eqSettings.preset))
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
                                        onPressed: () {
                                          ref.read(equalizerProvider.notifier).deleteCustomPreset(eqSettings.preset);
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _showSavePresetDialog(context),
                                icon: Icon(Icons.save_outlined, size: 18, color: colorScheme.primary),
                                label: Text('Save Custom Preset', style: TextStyle(color: colorScheme.primary)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Bands Adjustment',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...List.generate(bandsCount, (index) {
                              final double freq = eqSettings.frequencies[index];
                              final String label = formatFreq(freq);
                              final double val = currentGains[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        label,
                                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: val.clamp(-10.0, 10.0),
                                        min: -10.0,
                                        max: 10.0,
                                        onChanged: (newVal) {
                                          ref.read(equalizerProvider.notifier).setBand(index, newVal);
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)} dB',
                                        textAlign: TextAlign.end,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          const Divider(height: 28),
                          Text(
                            'Spatial Stereo & Bass Boost',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hardware bass boost and 3D virtualizer effect.',
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Hardware Bass Boost', style: textTheme.bodyMedium),
                              Text(
                                '${(eqSettings.bassBoostStrength / 10).toStringAsFixed(0)}%',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: eqSettings.bassBoostStrength.toDouble(),
                            min: 0,
                            max: 1000,
                            onChanged: (val) {
                              ref.read(equalizerProvider.notifier).setBassBoostStrength(val.toInt());
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Stereo Widening (3D Spatial)', style: textTheme.bodyMedium),
                              Text(
                                '${(eqSettings.virtualizerStrength / 10).toStringAsFixed(0)}%',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: eqSettings.virtualizerStrength.toDouble(),
                            min: 0,
                            max: 1000,
                            onChanged: (val) {
                              ref.read(equalizerProvider.notifier).setVirtualizerStrength(val.toInt());
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 4. Appearance
                  _buildSectionHeader(context, 'Appearance'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Visual Effects',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Controls blur shaders and backdrop filtering for GPU performance.',
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<VisualEffectsMode>(
                              segments: const [
                                ButtonSegment(
                                  value: VisualEffectsMode.off,
                                  label: Text('Off'),
                                  icon: Icon(Icons.blur_off_rounded),
                                ),
                                ButtonSegment(
                                  value: VisualEffectsMode.balanced,
                                  label: Text('Balanced'),
                                  icon: Icon(Icons.auto_awesome_rounded),
                                ),
                                ButtonSegment(
                                  value: VisualEffectsMode.full,
                                  label: Text('Full'),
                                  icon: Icon(Icons.blur_on_rounded),
                                ),
                              ],
                              selected: {effectsMode},
                              onSelectionChanged: (newSelection) {
                                ref.read(visualEffectsModeProvider.notifier).setMode(newSelection.first);
                              },
                            ),
                          ),
                          const Divider(height: 28),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Match artwork colours'),
                            subtitle: const Text('Tint player interface with the active album cover palette'),
                            value: ref.watch(matchArtworkColorsProvider),
                            onChanged: (val) {
                              ref.read(matchArtworkColorsProvider.notifier).state = val;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 5. Storage and downloads
                  _buildSectionHeader(context, 'Storage & Downloads'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manage Storage',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage offline audio files, cached album covers, and temporary signals.',
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    ref.read(homeTabIndexProvider.notifier).state = 2; // Jump to Library
                                  },
                                  icon: const Icon(Icons.download_done_rounded, size: 18),
                                  label: const Text('Downloads'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    PaintingBinding.instance.imageCache.clear();
                                    PaintingBinding.instance.imageCache.clearLiveImages();
                                    ref.read(homeLocalRepositoryProvider).clearSearchHistory();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Memory and search caches cleared successfully.')),
                                    );
                                  },
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                                  label: const Text('Clear Caches'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 6. Developer
                  _buildSectionHeader(context, 'Developer'),
                  Card.filled(
                    color: colorScheme.surfaceContainer,
                    child: ListTile(
                      leading: Icon(Icons.network_check_rounded, color: colorScheme.primary),
                      title: const Text('Test stream', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Diagnose stream resolution across client chain',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      onTap: () => showStreamDiagnosticsDialog(context, ref),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Footer
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'ECHONIX',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 3.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version 1.0.0 (Release Build)',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Developed & Created by Tharun Revinth',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '© 2026 Echonix Music. All Rights Reserved.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: dockHeight + 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSleepChip(int minutes, String label, int currentRemainingSeconds) {
    final bool isActive = (minutes == 0 && currentRemainingSeconds == 0) ||
        (minutes > 0 && currentRemainingSeconds > 0 && (currentRemainingSeconds - (minutes * 60)).abs() < 10);

    return FilterChip(
      selected: isActive,
      label: Text(label),
      onSelected: (_) {
        if (minutes == 0) {
          ref.read(sleepTimerProvider.notifier).stopTimer();
        } else {
          ref.read(sleepTimerProvider.notifier).setTimer(minutes);
        }
      },
    );
  }
}

String formatFreq(double val) {
  double hz = val;
  if (hz > 25000) {
    hz = hz / 1000;
  }
  if (hz >= 1000) {
    return '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz';
  } else {
    return '${hz.toStringAsFixed(0)} Hz';
  }
}

class EqCurveWidget extends ConsumerWidget {
  final ColorScheme colorScheme;
  final List<double> gains;
  final List<double> frequencies;
  final Function(int bandIdx, double gain) onBandChanged;

  const EqCurveWidget({
    super.key,
    required this.colorScheme,
    required this.gains,
    required this.frequencies,
    required this.onBandChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 150.0;
        const centerY = height / 2;
        final int bandsCount = gains.length;
        final List<double> xPoints = List.generate(bandsCount, (i) => width * (i + 0.5) / bandsCount);

        void handleTouch(Offset localPos) {
          int closestIndex = 0;
          double minDistance = double.maxFinite;
          for (int i = 0; i < bandsCount; i++) {
            final dist = (localPos.dx - xPoints[i]).abs();
            if (dist < minDistance) {
              minDistance = dist;
              closestIndex = i;
            }
          }

          final double deltaY = centerY - localPos.dy;
          const double maxDeltaY = centerY - 10.0;
          double gain = (deltaY / maxDeltaY) * 10.0;
          gain = gain.clamp(-10.0, 10.0);

          onBandChanged(closestIndex, gain);
        }

        return GestureDetector(
          onPanStart: (details) => handleTouch(details.localPosition),
          onPanUpdate: (details) => handleTouch(details.localPosition),
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: EqCurvePainter(
                  colorScheme: colorScheme,
                  gains: gains,
                  frequencies: frequencies,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class EqCurvePainter extends CustomPainter {
  final ColorScheme colorScheme;
  final List<double> gains;
  final List<double> frequencies;

  EqCurvePainter({
    required this.colorScheme,
    required this.gains,
    required this.frequencies,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;
    final int bandsCount = gains.length;

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    final zeroDbPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, centerY), Offset(width, centerY), zeroDbPaint);

    final List<double> xPoints = List.generate(bandsCount, (i) => width * (i + 0.5) / bandsCount);
    final List<double> yPoints = List.generate(bandsCount, (i) {
      final gain = gains[i];
      return centerY - (gain / 10.0) * (centerY - 10.0);
    });

    for (int i = 0; i < bandsCount; i++) {
      canvas.drawLine(Offset(xPoints[i], 0), Offset(xPoints[i], height), gridPaint);
    }

    final path = Path();
    path.moveTo(0, centerY);

    path.cubicTo(
      xPoints[0] * 0.5,
      centerY,
      xPoints[0] * 0.5,
      yPoints[0],
      xPoints[0],
      yPoints[0],
    );

    for (int i = 0; i < bandsCount - 1; i++) {
      final x1 = xPoints[i];
      final y1 = yPoints[i];
      final x2 = xPoints[i + 1];
      final y2 = yPoints[i + 1];

      final cx1 = x1 + (x2 - x1) * 0.5;
      final cy1 = y1;
      final cx2 = x1 + (x2 - x1) * 0.5;
      final cy2 = y2;

      path.cubicTo(cx1, cy1, cx2, cy2, x2, y2);
    }

    path.cubicTo(
      xPoints[bandsCount - 1] + (width - xPoints[bandsCount - 1]) * 0.5,
      yPoints[bandsCount - 1],
      xPoints[bandsCount - 1] + (width - xPoints[bandsCount - 1]) * 0.5,
      centerY,
      width,
      centerY,
    );

    final fillPath = Path.from(path);
    fillPath.lineTo(width, centerY);
    fillPath.lineTo(0, centerY);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colorScheme.primary.withValues(alpha: 0.35),
          colorScheme.primary.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [colorScheme.primary, colorScheme.secondary],
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    final handleInnerPaint = Paint()
      ..color = colorScheme.onPrimary
      ..style = PaintingStyle.fill;

    final handleOuterPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < bandsCount; i++) {
      canvas.drawCircle(
        Offset(xPoints[i], yPoints[i]),
        8.0,
        Paint()..color = colorScheme.primary.withValues(alpha: 0.3),
      );
      canvas.drawCircle(Offset(xPoints[i], yPoints[i]), 5.0, handleOuterPaint);
      canvas.drawCircle(Offset(xPoints[i], yPoints[i]), 3.0, handleInnerPaint);

      textPainter.text = TextSpan(
        text: formatFreq(frequencies[i]),
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(xPoints[i] - textPainter.width / 2, yPoints[i] + 12),
      );

      final double gain = gains[i];
      textPainter.text = TextSpan(
        text: '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(xPoints[i] - textPainter.width / 2, yPoints[i] - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant EqCurvePainter oldDelegate) {
    return oldDelegate.gains != gains ||
        oldDelegate.frequencies != frequencies ||
        oldDelegate.colorScheme != colorScheme;
  }
}
