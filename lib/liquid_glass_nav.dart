import 'dart:io';
import 'package:flutter/services.dart';

/// Bridge to iOS 26 Liquid Glass Bottom Navigation
class LiquidGlassNav {
  static const MethodChannel _channel = MethodChannel('v_policy_liquid_glass_nav');
  static const MethodChannel _navChannel = MethodChannel('v_policy_navigation');
  
  static Function(String)? _onNavigate;
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return Platform.isIOS;
  }
  
  /// Initialize Liquid Glass navigation with callback
  static Future<void> initialize(Function(String) onNavigate) async {
    _onNavigate = onNavigate;
    
    // Set up navigation listener
    _navChannel.setMethodCallHandler((call) async {
      if (call.method == 'navigate' && call.arguments is String) {
        _onNavigate?.call(call.arguments as String);
      }
    });
  }
  
  /// Show Liquid Glass navigation bar
  static Future<bool> show() async {
    try {
      return await _channel.invokeMethod('showLiquidGlassNav') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Hide Liquid Glass navigation bar
  static Future<bool> hide() async {
    try {
      return await _channel.invokeMethod('hideLiquidGlassNav') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Set selected tab index
  static Future<bool> setSelectedTab(int index) async {
    try {
      return await _channel.invokeMethod('setSelectedTab', index) ?? false;
    } catch (e) {
      return false;
    }
  }
}

