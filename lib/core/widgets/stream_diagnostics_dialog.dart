import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/providers/current_song_notifier.dart';
import 'package:client/core/python_backend.dart';

void showStreamDiagnosticsDialog(BuildContext context, WidgetRef ref, [String? specificVideoId]) {
  final targetId = specificVideoId ??
      ref.read(currentSongNotifierProvider)?.id ??
      'dQw4w9WgXcQ';

  showDialog(
    context: context,
    builder: (dialogContext) {
      return FutureBuilder<Map<String, dynamic>>(
        future: PythonBackend.diagnoseStream(targetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              title: const Text('Diagnosing Stream'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Testing stream clients for $targetId...'),
                ],
              ),
            );
          }

          final data = snapshot.data ?? {'success': false, 'error': snapshot.error?.toString() ?? 'Unknown error'};
          final prettyJson = const JsonEncoder.withIndent('  ').convert(data);

          return AlertDialog(
            title: Text('Stream Diagnostics: $targetId'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  prettyJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: prettyJson));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied diagnostics to clipboard')),
                  );
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}
