import 'package:client/core/theme/theme.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/core/python_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure AudioSession for music playback (required for Android Auto & lockscreen integration)
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {}

  try {
    await Permission.notification.request();
  } catch (_) {}

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.echonix.music.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: true,
    androidNotificationIcon: 'drawable/ic_notification',
  );

  final dir = await getApplicationDocumentsDirectory();
  Hive.defaultDirectory = dir.path;

  // Init Python synchronously — this only sets up paths and loads ytmusicapi
  // headers. It's fast (<2s) and must complete before home feed loads.
  await PythonBackend.init(dir.path);

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echonix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkThemeMode,
      home: const HomePage(),
    );
  }
}
