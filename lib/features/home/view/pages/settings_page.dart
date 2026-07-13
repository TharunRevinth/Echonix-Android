import 'package:client/core/theme/app_pallete.dart';
import 'package:client/core/python_backend.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/features/home/viewmodel/home_viewmodel.dart';
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
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Save Custom EQ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter preset name...',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  ref.read(equalizerProvider.notifier).saveCustomPreset(name);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved custom preset "$name"')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
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

  @override
  Widget build(BuildContext context) {
    final eqSettings = ref.watch(equalizerProvider);
    final remainingSleep = ref.watch(sleepTimerProvider);

    // List of active dropdown options combining built-in and user custom presets
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

    // Determine current gain values to pass to visualizer curve painter
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
      backgroundColor: Colors.black,
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF180828),
              Color(0xFF090310),
              Colors.black,
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 1. YT Music Connection Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isAuthenticated) ...[
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                                  SizedBox(width: 10),
                                  Text(
                                    'Connected to YouTube Music',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Your personalized home feed, history, likes, and library playlists are now synced.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _logout,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  minimumSize: const Size(double.infinity, 45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Logout / Disconnect Account', style: TextStyle(color: Colors.white)),
                              ),
                            ] else ...[
                              const Text(
                                'Connect YouTube Music Account',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Paste your YouTube Music cookie or cURL command below to fetch your personalized music library.',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _cookieController,
                                maxLines: 5,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Paste cookie string or cURL command here...',
                                  filled: true,
                                  fillColor: Pallete.borderColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _isConnecting ? null : _saveCredentials,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Pallete.whiteColor,
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isConnecting
                                    ? const CircularProgressIndicator(color: Colors.black)
                                    : const Text('Connect Account', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              if (_message.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _message,
                                  style: TextStyle(
                                    color: _message.contains('success') || _message.contains('Connected')
                                        ? Colors.green
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // 2. Sleep Timer / Bedtime Mode Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.bedtime_outlined, color: Colors.blueAccent, size: 24),
                                    SizedBox(width: 8),
                                    Text(
                                      'Bedtime Mode (Sleep Timer)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                if (remainingSleep > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatRemainingTime(remainingSleep),
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Set a timer to automatically pause music playback when you fall asleep.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
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

                      const SizedBox(height: 24),

                      // 3. Audio Equalizer Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.equalizer, color: Colors.purpleAccent, size: 24),
                                    SizedBox(width: 8),
                                    Text(
                                      'Audio Equalizer',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                Switch(
                                  value: eqSettings.enabled,
                                  onChanged: (val) {
                                    ref.read(equalizerProvider.notifier).toggle(val);
                                  },
                                  activeColor: Colors.purpleAccent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Customize the frequencies and choose presets for your perfect listening experience.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            if (eqSettings.enabled) ...[
                              const SizedBox(height: 16),

                              // Interactive Bezier Curve EQ widget (Spotify style!)
                              const Text(
                                'Interactive Curve Control (Drag to adjust)',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              EqCurveWidget(
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
                                  const Text(
                                    'Preset Mode',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  Row(
                                    children: [
                                      DropdownButton<String>(
                                        value: dropdownItems.contains(eqSettings.preset) ? eqSettings.preset : 'Normal',
                                        dropdownColor: const Color(0xFF1E1E1E),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () {
                                            ref.read(equalizerProvider.notifier).deleteCustomPreset(eqSettings.preset);
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              
                              // Save custom Preset CTA
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showSavePresetDialog(context),
                                    icon: const Icon(Icons.save_outlined, color: Colors.purpleAccent, size: 18),
                                    label: const Text('Save Custom Preset', style: TextStyle(color: Colors.purpleAccent, fontSize: 13)),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              const Text(
                                'Bands Adjustment',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              
                              // Build dynamic list of sliders based on frequency count
                              ...List.generate(bandsCount, (index) {
                                final double freq = eqSettings.frequencies[index];
                                final String label = formatFreq(freq);
                                double val = currentGains[index];

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          label,
                                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: val.clamp(-10.0, 10.0),
                                          min: -10.0,
                                          max: 10.0,
                                          activeColor: Colors.purpleAccent,
                                          inactiveColor: Colors.white12,
                                          onChanged: (newVal) {
                                            ref.read(equalizerProvider.notifier).setBand(index, newVal);
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 50,
                                        child: Text(
                                          '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)} dB',
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 160), // Space to scroll past floating music slab and glass tab bar
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSleepChip(int minutes, String label, int currentRemainingSeconds) {
    final bool isActive = (minutes == 0 && currentRemainingSeconds == 0) ||
        (minutes > 0 && currentRemainingSeconds > 0 && (currentRemainingSeconds - (minutes * 60)).abs() < 10);

    return GestureDetector(
      onTap: () {
        if (minutes == 0) {
          ref.read(sleepTimerProvider.notifier).stopTimer();
        } else {
          ref.read(sleepTimerProvider.notifier).setTimer(minutes);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blueAccent : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blueAccent : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// Helper to format frequency
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

// -----------------------------------------------------------------------------
// Interactive Spotify-style EQ curve widgets & custom painters
// -----------------------------------------------------------------------------
class EqCurveWidget extends ConsumerWidget {
  final List<double> gains;
  final List<double> frequencies;
  final Function(int bandIdx, double gain) onBandChanged;

  const EqCurveWidget({
    super.key,
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
        final centerY = height / 2;
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
          final double maxDeltaY = centerY - 10.0;
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
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: EqCurvePainter(gains: gains, frequencies: frequencies),
              ),
            ),
          ),
        );
      },
    );
  }
}

class EqCurvePainter extends CustomPainter {
  final List<double> gains;
  final List<double> frequencies;

  EqCurvePainter({required this.gains, required this.frequencies});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;
    final int bandsCount = gains.length;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.0;
    
    final zeroDbPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    // Draw 0 dB dashed horizontal line
    canvas.drawLine(Offset(0, centerY), Offset(width, centerY), zeroDbPaint);

    final List<double> xPoints = List.generate(bandsCount, (i) => width * (i + 0.5) / bandsCount);
    final List<double> yPoints = List.generate(bandsCount, (i) {
      final gain = gains[i];
      return centerY - (gain / 10.0) * (centerY - 10.0);
    });

    // Draw vertical frequency lines
    for (int i = 0; i < bandsCount; i++) {
      canvas.drawLine(Offset(xPoints[i], 0), Offset(xPoints[i], height), gridPaint);
    }

    final path = Path();
    path.moveTo(0, centerY);
    
    path.cubicTo(
      xPoints[0] * 0.5, centerY,
      xPoints[0] * 0.5, yPoints[0],
      xPoints[0], yPoints[0],
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
      xPoints[bandsCount - 1] + (width - xPoints[bandsCount - 1]) * 0.5, yPoints[bandsCount - 1],
      xPoints[bandsCount - 1] + (width - xPoints[bandsCount - 1]) * 0.5, centerY,
      width, centerY,
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
          Colors.purpleAccent.withOpacity(0.25),
          Colors.blueAccent.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.purpleAccent, Colors.blueAccent],
      ).createShader(Rect.fromLTRB(0, 0, width, height))
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    canvas.drawPath(path, linePaint);

    final handleInnerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final handleOuterPaint = Paint()
      ..color = Colors.purpleAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < bandsCount; i++) {
      // Glow circle
      canvas.drawCircle(
        Offset(xPoints[i], yPoints[i]),
        8.0,
        Paint()..color = Colors.purpleAccent.withOpacity(0.3),
      );
      // Outer border circle
      canvas.drawCircle(Offset(xPoints[i], yPoints[i]), 5.0, handleOuterPaint);
      // Inner circle
      canvas.drawCircle(Offset(xPoints[i], yPoints[i]), 3.0, handleInnerPaint);

      // Draw Frequency label below circle
      textPainter.text = TextSpan(
        text: formatFreq(frequencies[i]),
        style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w600),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(xPoints[i] - textPainter.width / 2, yPoints[i] + 12),
      );

      // Draw Gain label above circle
      final double gain = gains[i];
      textPainter.text = TextSpan(
        text: '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
        style: const TextStyle(color: Colors.purpleAccent, fontSize: 8, fontWeight: FontWeight.bold),
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
    return oldDelegate.gains != gains || oldDelegate.frequencies != frequencies;
  }
}
