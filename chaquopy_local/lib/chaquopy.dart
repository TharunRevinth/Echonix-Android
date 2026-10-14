import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Static class for accessing Python backend via Chaquopy.
class Chaquopy {
  static const MethodChannel _channel = MethodChannel('chaquopy');

  /// Invoke a Python function by name on either the priority or background lane.
  static Future<String> invoke(
    String fn,
    Map<String, dynamic> args, {
    String lane = 'background',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final String? res = await _channel.invokeMethod<String>('invoke', {
        'fn': fn,
        'args': jsonEncode(args),
        'lane': lane,
      }).timeout(
        timeout,
        onTimeout: () => jsonEncode({'success': false, 'error': 'timeout'}),
      );
      return res ?? jsonEncode({'success': false, 'error': 'null response'});
    } catch (e) {
      return jsonEncode({'success': false, 'error': e.toString()});
    }
  }

  /// Legacy helper for backwards compatibility.
  static Future<Map<String, dynamic>> executeCode(String code) async {
    return {'textOutputOrError': ''};
  }
}


