import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void showAddToPlaylistDialog(BuildContext context, WidgetRef ref, SongModel song) {
  showDialog(
    context: context,
    builder: (context) {
      return Consumer(
        builder: (context, ref, child) {
          final playlists = ref.watch(localPlaylistsProvider);
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Add to Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add, color: Colors.purpleAccent),
                    title: const Text('Create Playlist', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    onTap: () {
                      _showCreatePlaylistInline(context, ref, song);
                    },
                  ),
                  const Divider(color: Colors.white10),
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          'No playlists yet.\nTap above to create one!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final p = playlists[index];
                          return ListTile(
                            title: Text(p.name, style: const TextStyle(color: Colors.white)),
                            onTap: () {
                              ref.read(localPlaylistsProvider.notifier).addSongToPlaylist(p.id, song);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Added to "${p.name}"')),
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

void _showCreatePlaylistInline(BuildContext context, WidgetRef ref, SongModel song) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Playlist Name',
          hintStyle: TextStyle(color: Colors.grey),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent, width: 2)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
        ),
        TextButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              final newId = await ref.read(localPlaylistsProvider.notifier).createPlaylist(name);
              await ref.read(localPlaylistsProvider.notifier).addSongToPlaylist(newId, song);
              if (context.mounted) {
                // Close the create dialog
                Navigator.pop(context);
                // Close the picker dialog
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created "$name" and added track!')),
                );
              }
            }
          },
          child: const Text('Create', style: TextStyle(color: Colors.purpleAccent)),
        ),
      ],
    ),
  );
}
