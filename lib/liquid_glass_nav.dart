import 'dart:io';
import 'package:flutter/services.dart';

/// Bridge to iOS 26 Liquid Glass Bottom Navigation
class LiquidGlassNav {
  static const MethodChannel _channel = MethodChannel('v_policy_liquid_glass_nav');
  static const MethodChannel _navChannel = MethodChannel('v_policy_navigation');
  
  static bool _isSupported = false;
  static Function(String)? _onNavigate;
  
  /// Check if Liquid Glass is supported (iOS 26+)
  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    
    try {
      _isSupported = await _channel.invokeMethod('isLiquidGlassSupported') ?? false;
      return _isSupported;
    } catch (e) {
      return false;
    }
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
    if (!_isSupported) return false;
    
    try {
      return await _channel.invokeMethod('showLiquidGlassNav') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Hide Liquid Glass navigation bar
  static Future<bool> hide() async {
    if (!_isSupported) return false;
    
    try {
      return await _channel.invokeMethod('hideLiquidGlassNav') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Set selected tab index
  static Future<bool> setSelectedTab(int index) async {
    if (!_isSupported) return false;
    
    try {
      return await _channel.invokeMethod('setSelectedTab', index) ?? false;
    } catch (e) {
      return false;
    }
  }
}

