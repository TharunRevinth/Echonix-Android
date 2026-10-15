import 'package:client/core/theme/theme.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/core/providers/bootstrap_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('[Echonix][Error] ${details.exceptionAsString()} \n${details.stack}');
    }
  };

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.echonix.music.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
    );
  } catch (e, st) {
    debugPrint('[Echonix][Init] JustAudioBackground.init failed: $e\n$st');
  }

  final dir = await getApplicationDocumentsDirectory();
  Hive.defaultDirectory = dir.path;

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly trigger bootstrap on first frame
    ref.watch(bootstrapProvider);

    return MaterialApp(
      title: 'Echonix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkThemeMode,
      home: const HomePage(),
    );
  }
}
