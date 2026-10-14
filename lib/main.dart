import 'package:client/core/theme/theme.dart';
import 'package:client/features/home/view/pages/home_page.dart';
import 'package:client/core/providers/bootstrap_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  debugPrint('[Echonix] 1. main() invoked');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Echonix] 2. WidgetsFlutterBinding initialized');

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Echonix][Error] ${details.exceptionAsString()} \n${details.stack}');
  };

  debugPrint('[Echonix] 3. calling getApplicationDocumentsDirectory()');
  final dir = await getApplicationDocumentsDirectory();
  debugPrint('[Echonix] 4. getApplicationDocumentsDirectory resolved: ${dir.path}');
  Hive.defaultDirectory = dir.path;
  debugPrint('[Echonix] 5. Hive.defaultDirectory set');

  debugPrint('[Echonix] 6. calling runApp()');
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
  debugPrint('[Echonix] 7. runApp() completed');
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[Echonix] 8. MyApp build() entered');
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
