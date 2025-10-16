import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Bridge for iOS 26+ Liquid Glass Info Button
class LiquidGlassInfoButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_info_button');
  
  static Future<bool> isSupported() async {
    try {
      final bool? result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking liquid glass support: $e');
      return false;
    }
  }
  
  static Future<bool> show() async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassInfoButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass info button: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('disableNativeLiquidGlassInfoButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass info button: $e');
      return false;
    }
  }
  
  static void setOnInfoButtonTappedCallback(VoidCallback callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onInfoButtonTapped') {
        callback();
      }
    });
  }
}

