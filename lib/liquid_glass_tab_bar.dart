import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Bridge for iOS 26+ Liquid Glass Terminal Tab Bar
class LiquidGlassTabBar {
  static const MethodChannel _channel = MethodChannel('liquid_glass_tab_bar');
  
  static Future<bool> isSupported() async {
    try {
      final bool? result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking liquid glass support: $e');
      return false;
    }
  }
  
  static Future<bool> show({
    required List<Map<String, String>> tabs,
    required int activeIndex,
    required bool canAddTab,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('showLiquidGlassTabBar', {
        'tabs': tabs,
        'activeIndex': activeIndex,
        'canAddTab': canAddTab,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass tab bar: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('hideLiquidGlassTabBar');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass tab bar: $e');
      return false;
    }
  }
  
  static Future<bool> updateTabs({
    required List<Map<String, String>> tabs,
    required int activeIndex,
    required bool canAddTab,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('updateTabs', {
        'tabs': tabs,
        'activeIndex': activeIndex,
        'canAddTab': canAddTab,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating tabs: $e');
      return false;
    }
  }
  
  static void setCallbacks({
    required Function(int index) onTabSelected,
    required Function(int index) onTabClosed,
    required VoidCallback onNewTab,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTabSelected':
          final int index = call.arguments as int;
          onTabSelected(index);
          break;
        case 'onTabClosed':
          final int index = call.arguments as int;
          onTabClosed(index);
          break;
        case 'onNewTab':
          onNewTab();
          break;
      }
    });
  }
}

