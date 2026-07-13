import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

String rgbToHex(Color color) {
  return '${color.red.toRadixString(16).padLeft(2, '0')}${color.green.toRadixString(16).padLeft(2, '0')}${color.blue.toRadixString(16).padLeft(2, '0')}';
}

Color hexToColor(String hex) {
  try {
    if (hex.isEmpty) return Colors.grey;
    final cleaned = hex.replaceAll('#', '').trim();
    return Color(int.parse(cleaned, radix: 16) + 0xFF000000);
  } catch (_) {
    return Colors.grey;
  }
}

void showSnackBar(BuildContext context, String content) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(content),
      ),
    );
}

Future<File?> pickImage() async {
  try {
    final filePickerRes = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (filePickerRes != null) {
      return File(filePickerRes.files.first.xFile.path);
    }
    return null;
  } catch (e) {
    return null;
  }
}

Future<File?> pickAudio() async {
  try {
    final filePickerRes = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (filePickerRes != null) {
      return File(filePickerRes.files.first.xFile.path);
    }
    return null;
  } catch (e) {
    return null;
  }
}

String getHighQualityThumbnail(String url) {
  if (url.isEmpty) return url;
  
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    // 1. Scale up width/height specifier (e.g. =w120-h120 -> =w500-h500)
    final wExp = RegExp(r'=w\d+-h\d+');
    if (wExp.hasMatch(url)) {
      return url.replaceFirst(wExp, '=w500-h500');
    }
    // 2. Scale up single size specifier (e.g. =s192 -> =s500)
    final sExp = RegExp(r'=s\d+');
    if (sExp.hasMatch(url)) {
      return url.replaceFirst(sExp, '=s500');
    }
  }
  
  if (url.contains('ytimg.com')) {
    var cleanUrl = url;
    if (cleanUrl.contains('?')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.indexOf('?'));
    }
    return cleanUrl
        .replaceAll('/default.jpg', '/hqdefault.jpg')
        .replaceAll('/mqdefault.jpg', '/hqdefault.jpg')
        .replaceAll('/sddefault.jpg', '/hqdefault.jpg');
  }
  
  return url;
}
