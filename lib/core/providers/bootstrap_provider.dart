import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:client/core/python_backend.dart';

final bootstrapProvider = FutureProvider<void>((ref) async {
  final dir = await getApplicationDocumentsDirectory();

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {}

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.echonix.music.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
    );
  } catch (_) {}

  // PythonBackend.init runs on priority lane
  await PythonBackend.init(dir.path);
});
