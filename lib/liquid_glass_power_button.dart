import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Bridge for iOS 26+ Liquid Glass Power Button
class LiquidGlassPowerButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_power_button');
  
  static Future<bool> isSupported() async {
    try {
      final bool? result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking liquid glass support: $e');
      return false;
    }
  }
  
  static Future<bool> show({required bool isConnected}) async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassPowerButton', {
        'isConnected': isConnected,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass power button: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('disableNativeLiquidGlassPowerButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass power button: $e');
      return false;
    }
  }
  
  static Future<bool> updateState({required bool isConnected}) async {
    try {
      final bool? result = await _channel.invokeMethod('updatePowerButtonState', {
        'isConnected': isConnected,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating power button state: $e');
      return false;
    }
  }
  
  static void setOnPowerButtonTappedCallback(VoidCallback callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPowerButtonTapped') {
        callback();
      }
    });
  }
}

