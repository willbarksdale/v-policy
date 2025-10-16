import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Bridge for iOS 26+ Liquid Glass Play Button
class LiquidGlassPlayButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_play_button');
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return true;
  }
  
  static Future<bool> show({required bool isLoading}) async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassPlayButton', {
        'isLoading': isLoading,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass play button: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('disableNativeLiquidGlassPlayButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass play button: $e');
      return false;
    }
  }
  
  static Future<bool> updateState({required bool isLoading}) async {
    try {
      final bool? result = await _channel.invokeMethod('updatePlayButtonState', {
        'isLoading': isLoading,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating play button state: $e');
      return false;
    }
  }
  
  static void setOnPlayButtonTappedCallback(VoidCallback callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPlayButtonTapped') {
        callback();
      }
    });
  }
}

