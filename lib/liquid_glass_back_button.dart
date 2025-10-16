import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Bridge for iOS 26+ Liquid Glass Back Button
class LiquidGlassBackButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_back_button');
  
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
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassBackButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass back button: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('disableNativeLiquidGlassBackButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass back button: $e');
      return false;
    }
  }
  
  static void setOnBackButtonTappedCallback(VoidCallback callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBackButtonTapped') {
        callback();
      }
    });
  }
}

