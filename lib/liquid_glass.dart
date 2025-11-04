import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

// ============================================================================
// LIQUID GLASS - iOS 26+ Native UI Components
// ============================================================================
// Consolidated bridge for all Liquid Glass native iOS components.
// This provides Flutter access to SwiftUI-based "liquid glass" UI elements.
// ============================================================================

// ============================================================================
// TERMINAL TAB BAR
// ============================================================================
/// Terminal tab bar with native iOS 26 liquid glass design
class LiquidGlassTabBar {
  static const MethodChannel _channel = MethodChannel('liquid_glass_tab_bar');
  static bool _callbacksSet = false; // Track if callbacks are already set
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return true;
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
    // Only set callbacks once to prevent multiple handlers
    if (_callbacksSet) {
      debugPrint('⚠️ LiquidGlassTabBar callbacks already set, skipping');
      return;
    }
    
    debugPrint('✅ Setting LiquidGlassTabBar callbacks (first time)');
    _callbacksSet = true;
    
    _channel.setMethodCallHandler((call) async {
      debugPrint('📞 LiquidGlassTabBar received: ${call.method}');
      
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
          debugPrint('🔔 onNewTab callback triggered');
          onNewTab();
          break;
      }
    });
  }
}

// ============================================================================
// TERMINAL INPUT BAR
// ============================================================================
/// Native terminal input bar with keyboard handling
class LiquidGlassTerminalInput {
  static const MethodChannel _channel = MethodChannel('liquid_glass_terminal_input');
  
  static Function(String)? _onCommandSent;
  static Function(String)? _onInputChanged;
  static Function()? _onDismissKeyboard;
  static Function()? _onKeyboardShow;
  static Function()? _onKeyboardHide;

  /// Check if Liquid Glass is supported (iOS 26+)
  static Future<bool> isSupported() async {
    try {
      final bool result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Initialize the terminal input with callbacks
  static Future<void> initialize({
    required Function(String) onCommandSent,
    Function(String)? onInputChanged,
    Function()? onDismissKeyboard,
    Function()? onKeyboardShow,
    Function()? onKeyboardHide,
  }) async {
    _onCommandSent = onCommandSent;
    _onInputChanged = onInputChanged;
    _onDismissKeyboard = onDismissKeyboard;
    _onKeyboardShow = onKeyboardShow;
    _onKeyboardHide = onKeyboardHide;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCommandSent':
          final text = call.arguments['text'] as String?;
          if (text != null) {
            _onCommandSent?.call(text);
          }
          break;
        case 'onInputChanged':
          final text = call.arguments['text'] as String?;
          if (text != null) {
            _onInputChanged?.call(text);
          }
          break;
        case 'onDismissKeyboard':
          _onDismissKeyboard?.call();
          break;
        case 'onKeyboardShow':
          _onKeyboardShow?.call();
          break;
        case 'onKeyboardHide':
          _onKeyboardHide?.call();
          break;
      }
    });
  }

  /// Show the terminal input bar
  static Future<bool> show({
    String placeholder = 'Type commands here...',
  }) async {
    try {
      final bool result = await _channel.invokeMethod('showTerminalInput', {
        'placeholder': placeholder,
      });
      return result;
    } catch (e) {
      debugPrint('Error showing terminal input: $e');
      return false;
    }
  }

  /// Hide the terminal input bar
  static Future<bool> hide() async {
    try {
      final bool result = await _channel.invokeMethod('hideTerminalInput');
      return result;
    } catch (e) {
      debugPrint('Error hiding terminal input: $e');
      return false;
    }
  }

  /// Clear the terminal input text
  static Future<bool> clear() async {
    try {
      final bool result = await _channel.invokeMethod('clearTerminalInput');
      return result;
    } catch (e) {
      debugPrint('Error clearing terminal input: $e');
      return false;
    }
  }

  /// Set the terminal input text programmatically
  static Future<bool> setText(String text) async {
    try {
      final bool result = await _channel.invokeMethod('setTerminalInputText', {
        'text': text,
      });
      return result;
    } catch (e) {
      debugPrint('Error setting terminal input text: $e');
      return false;
    }
  }

  /// Dismiss the keyboard
  static Future<bool> dismissKeyboard() async {
    try {
      final bool result = await _channel.invokeMethod('dismissKeyboard');
      return result;
    } catch (e) {
      debugPrint('Error dismissing keyboard: $e');
      return false;
    }
  }
}

// ============================================================================
// BOTTOM NAVIGATION BAR
// ============================================================================
/// Native bottom navigation bar with liquid glass design
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

// ============================================================================
// POWER BUTTON (SSH Screen)
// ============================================================================
/// Power button for SSH connection control
class LiquidGlassPowerButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_power_button');
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return true;
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

// ============================================================================
// INFO BUTTON (SSH Screen)
// ============================================================================
/// Info button for navigation to info/help screen
class LiquidGlassInfoButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_info_button');
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return true;
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

// ============================================================================
// PLAY BUTTON (Preview Screen)
// ============================================================================
/// Play button for preview screen URL loading
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

// ============================================================================
// BACK BUTTON (Info Screen)
// ============================================================================
/// Back button for navigating back from info screen
class LiquidGlassBackButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_back_button');
  
  /// iOS 26+ always supports Liquid Glass
  static Future<bool> isSupported() async {
    return true;
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

