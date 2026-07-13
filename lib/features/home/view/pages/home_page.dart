import 'dart:ui';
import 'package:client/core/theme/app_pallete.dart';
import 'package:client/features/home/view/pages/library_page.dart';
import 'package:client/features/home/view/pages/songs_page.dart';
import 'package:client/features/home/view/pages/search_page.dart';
import 'package:client/features/home/view/pages/settings_page.dart';
import 'package:client/features/home/view/widgets/music_slab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);
final searchQueryProvider = StateProvider<String>((ref) => '');

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  final pages = const [
    SongsPage(),
    SearchPage(),
    LibraryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(homeTabIndexProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true, // Extends body under the transparent bottom navigation bar for a fully integrated gradient flow
      body: Stack(
        children: [
          // Render the active view page
          Positioned.fill(
            child: pages[selectedIndex],
          ),
          
          // Floating Music Slab positioned exactly above the fixed bottom navigation bar
          const Positioned(
            bottom: 76,
            left: 12,
            right: 12,
            child: MusicSlab(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 56 + MediaQuery.of(context).padding.bottom,
        color: Colors.transparent, // Fully transparent background
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(ref, 0, 'assets/images/home_filled.png', 'assets/images/home_unfilled.png', null, 'Home', selectedIndex),
              _buildNavItem(ref, 1, null, null, Icons.search, 'Search', selectedIndex),
              _buildNavItem(ref, 2, 'assets/images/library.png', 'assets/images/library.png', null, 'Library', selectedIndex),
              _buildNavItem(ref, 3, null, null, Icons.settings, 'Settings', selectedIndex),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    WidgetRef ref,
    int index,
    String? filledAssetPath,
    String? unfilledAssetPath,
    IconData? iconData,
    String label,
    int selectedIndex,
  ) {
    final isSelected = selectedIndex == index;
    final color = isSelected ? Colors.white : Colors.grey;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact(); // Tactile click feedback
          ref.read(homeTabIndexProvider.notifier).state = index;
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconData != null)
              Icon(
                iconData,
                color: color,
                size: 24,
              )
            else
              Image.asset(
                isSelected ? (filledAssetPath ?? '') : (unfilledAssetPath ?? ''),
                color: color,
                width: 22,
                height: 22,
              ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
