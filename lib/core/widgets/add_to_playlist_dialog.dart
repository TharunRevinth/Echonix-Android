import 'package:client/features/home/models/song_model.dart';
import 'package:client/features/home/viewmodel/local_playlists_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void showAddToPlaylistDialog(BuildContext context, WidgetRef ref, SongModel song) {
  showDialog(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;

      return Consumer(
        builder: (context, ref, child) {
          final playlists = ref.watch(localPlaylistsProvider);
          return AlertDialog(
            backgroundColor: scheme.surfaceContainerHigh,
            title: Text(
              'Add to Playlist',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.add, color: scheme.primary),
                    title: Text(
                      'Create Playlist',
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      _showCreatePlaylistInline(context, ref, song);
                    },
                  ),
                  Divider(color: scheme.outlineVariant),
                  if (playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          'No playlists yet.\nTap above to create one!',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
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
                            title: Text(
                              p.name,
                              style: textTheme.titleMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
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
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;

      return AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: Text(
          'New Playlist',
          style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        ),
        content: TextField(
          controller: controller,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: scheme.primary),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final newId = await ref.read(localPlaylistsProvider.notifier).createPlaylist(name);
                await ref.read(localPlaylistsProvider.notifier).addSongToPlaylist(newId, song);
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created "$name" and added track!')),
                  );
                }
              }
            },
            child: Text(
              'Create',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
