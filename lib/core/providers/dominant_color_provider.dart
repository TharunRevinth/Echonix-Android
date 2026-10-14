import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';

final dominantColorProvider =
    FutureProvider.family<Color, String>((ref, imageUrl) async {
  if (imageUrl.isEmpty) {
    return const Color(0xFF212121);
  }

  final Box box = Hive.box();
  final dynamic rawCache = box.get('palette_cache');
  final Map<String, dynamic> cache =
      rawCache is Map ? Map<String, dynamic>.from(rawCache) : {};

  if (cache.containsKey(imageUrl)) {
    final val = cache[imageUrl];
    if (val is int) {
      return Color(val);
    }
  }

  try {
    final imageProvider = ResizeImage(
      CachedNetworkImageProvider(imageUrl),
      width: 64,
      height: 64,
    );
    final palette = await PaletteGenerator.fromImageProvider(
      imageProvider,
      maximumColorCount: 4,
    );
    final color = palette.dominantColor?.color ?? const Color(0xFF212121);

    cache[imageUrl] = color.toARGB32();
    while (cache.length > 300) {
      final oldestKey = cache.keys.first;
      cache.remove(oldestKey);
    }
    box.put('palette_cache', cache);
    return color;
  } catch (_) {
    return const Color(0xFF212121);
  }
});
