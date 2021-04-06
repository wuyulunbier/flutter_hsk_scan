import 'dart:async';

import 'package:flutter/services.dart';

class Flutterhskscan {
  static const MethodChannel _channel =
      const MethodChannel('flutterhskscan');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
