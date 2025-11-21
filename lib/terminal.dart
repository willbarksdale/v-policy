import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'ssh.dart';
import 'preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// LIQUID GLASS - Terminal Tabs (Native iOS Component)
// ============================================================================
/// Native terminal tab buttons at the top of the terminal screen
class LiquidGlassTerminalTabs {
  static const MethodChannel _channel = MethodChannel('liquid_glass_terminal_tabs');
  
  static Future<bool> isSupported() async {
    try {
      final bool? result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking liquid glass tabs support: $e');
      return false;
    }
  }
  
  static Future<bool> show({
    required int activeTab,
    required int tabCount,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('show', {
        'activeTab': activeTab,
        'tabCount': tabCount,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass tabs: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('hide');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass tabs: $e');
      return false;
    }
  }
  
  static Future<bool> updateTabs({
    required int activeTab,
    required int tabCount,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('updateTabs', {
        'activeTab': activeTab,
        'tabCount': tabCount,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating liquid glass tabs: $e');
      return false;
    }
  }
  
  static Future<void> initialize({
    required Function(int index) onTabTapped,
    required Function(int index) onTabLongPressed,
  }) async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTabTapped':
          final int index = call.arguments['index'] as int;
          onTabTapped(index);
          break;
        case 'onTabLongPressed':
          final int index = call.arguments['index'] as int;
          onTabLongPressed(index);
          break;
      }
    });
  }
}

// ============================================================================
// LIQUID GLASS - Terminal Input (Native iOS Component)
// ============================================================================
/// Native terminal input bar with keyboard handling
class LiquidGlassTerminalInput {
  static const MethodChannel _channel = MethodChannel('liquid_glass_terminal_input');
  
  static Function(String)? _onCommandSent;
  static Function(String)? _onInputChanged;
  static Function()? _onDismissKeyboard;
  static Function()? _onKeyboardShow;
  static Function()? _onKeyboardHide;

  static Future<bool> isSupported() async {
    try {
      final bool result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result;
    } catch (e) {
      return false;
    }
  }

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
          if (text != null) _onCommandSent?.call(text);
          break;
        case 'onInputChanged':
          final text = call.arguments['text'] as String?;
          if (text != null) _onInputChanged?.call(text);
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

  static Future<bool> show({String placeholder = 'Type commands here...'}) async {
    try {
      final bool result = await _channel.invokeMethod('showTerminalInput', {'placeholder': placeholder});
      return result;
    } catch (e) {
      debugPrint('Error showing terminal input: $e');
      return false;
    }
  }

  static Future<bool> hide() async {
    try {
      final bool result = await _channel.invokeMethod('hideTerminalInput');
      return result;
    } catch (e) {
      debugPrint('Error hiding terminal input: $e');
      return false;
    }
  }

  static Future<bool> clear() async {
    try {
      final bool result = await _channel.invokeMethod('clearTerminalInput');
      return result;
    } catch (e) {
      debugPrint('Error clearing terminal input: $e');
      return false;
    }
  }

  static Future<bool> setText(String text) async {
    try {
      final bool result = await _channel.invokeMethod('setTerminalInputText', {'text': text});
      return result;
    } catch (e) {
      debugPrint('Error setting terminal input text: $e');
      return false;
    }
  }

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
// TMUX SERVICE - Persistent Terminal Sessions
// ============================================================================

/// TmuxService manages 3 persistent terminal sessions via tmux
/// Sessions are named v_session_0, v_session_1, v_session_2
/// They persist across app restarts and reconnections
class TmuxService {
  final SshService _sshService;
  final Ref? _ref; // Optional ref for updating providers
  
  // Fixed session names for persistence
  static const List<String> sessionNames = ['v_session_1', 'v_session_2', 'v_session_3'];
  
  // One SSH session per terminal tab
  final List<dartssh2.SSHSession?> _sessions = [null, null, null];
  final List<StreamSubscription?> _subscriptions = [null, null, null];
  
  bool _isInitialized = false;
  int _activeSessionIndex = 0;
  
  final StreamController<TmuxEvent> _eventController = StreamController.broadcast();
  Stream<TmuxEvent> get events => _eventController.stream;
  
  // Output buffering for each session to prevent UI flooding during rapid updates
  final List<StringBuffer> _outputBuffers = [StringBuffer(), StringBuffer(), StringBuffer()];
  final List<Timer?> _flushTimers = [null, null, null];
  final List<DateTime> _lastFlushTimes = [DateTime.now(), DateTime.now(), DateTime.now()];
  
  // Adaptive buffer delay: shorter for initial bursts, longer for sustained streams
  static const Duration _shortFlushDelay = Duration(milliseconds: 8);  // Initial burst
  static const Duration _longFlushDelay = Duration(milliseconds: 16);  // Sustained stream
  static const Duration _burstThreshold = Duration(milliseconds: 100); // Time to consider it a "burst"
  
  TmuxService(this._sshService, [this._ref]);
  
  bool get isInitialized => _isInitialized;
  int get activeSessionIndex => _activeSessionIndex;
  
  /// Check if tmux is available on the server
  /// Returns true if tmux is found, false otherwise
  /// Uses a single optimized command to reduce SSH channel usage
  Future<bool> checkTmuxInstalled() async {
    if (!_sshService.isConnected) {
      debugPrint('❌ Cannot check tmux: SSH not connected');
      return false;
    }
    
    try {
      debugPrint('🔍 Checking for tmux...');
      
      // Optimized: Use a single command that tries all methods in sequence
      // This uses only ONE SSH channel instead of three
      // The command will exit on first success
      final result = await _sshService.runCommandLenient(
        'command -v tmux >/dev/null 2>&1 && echo "FOUND" || '
        'which tmux >/dev/null 2>&1 && echo "FOUND" || '
        'tmux -V >/dev/null 2>&1 && echo "FOUND" || '
        'echo "NOT_FOUND"',
        maxRetries: 5, // Increase retries for better reliability
      );
      
      if (result == null) {
        debugPrint('⚠️ tmux detection returned null');
        return false;
      }
      
      final output = result.trim().toUpperCase();
      debugPrint('📋 tmux detection output: "$output"');
      
      if (output.contains('FOUND')) {
        debugPrint('✅ tmux found on system');
        return true;
      }
      
      if (output.contains('NOT_FOUND') || output.isEmpty) {
        debugPrint('❌ tmux not found in PATH');
        return false;
      }
      
      // Unexpected output - log it and assume not found
      debugPrint('⚠️ Unexpected tmux detection output: "$output"');
      return false;
      
    } catch (e) {
      debugPrint('❌ Error checking tmux: $e');
      return false;
    }
  }
  
  /// Initialize all 3 persistent tmux sessions
  /// Attempts to attach to existing sessions, creates new ones if needed
  Future<bool> initialize({int terminalWidth = 40, int terminalHeight = 50}) async {
    // Prevent re-initialization without cleanup
    if (_isInitialized) {
      debugPrint('⚠️ Tmux already initialized, cleaning up before re-init');
      _cleanup();
    }
    
    if (!_sshService.isConnected) {
      debugPrint('❌ Cannot initialize tmux: SSH not connected');
      return false;
    }
    
    try {
      debugPrint('🚀 Initializing 3 persistent tmux sessions (${terminalWidth}x$terminalHeight)...');
      
      // Create/attach to each session
      for (int i = 0; i < 3; i++) {
        final sessionName = sessionNames[i];
        debugPrint('📝 Setting up session $i: $sessionName');
        
        // Check if session already exists
        final checkResult = await _sshService.runCommandLenient(
          'tmux has-session -t $sessionName 2>/dev/null && echo "exists" || echo "new"'
        );
        
        final sessionExists = checkResult?.trim() == 'exists';
        debugPrint(sessionExists 
          ? '   ✅ Session $sessionName exists, attaching...' 
          : '   🆕 Creating new session $sessionName...'
        );
        
        // Open SSH shell session with specified terminal size
        final session = await _sshService.shell(
          terminalWidth: terminalWidth,
          terminalHeight: terminalHeight,
        );
        if (session == null) {
          debugPrint('   ❌ Failed to open shell for session $i');
          return false;
        }
        
        // Attach to tmux session (or create if new)
        if (sessionExists) {
          session.write(utf8.encode('tmux attach-session -t $sessionName\n'));
        } else {
          session.write(utf8.encode('tmux new-session -s $sessionName\n'));
        }
        
        // Store session
        _sessions[i] = session;
        
        // Listen to output (stdout only - stderr is for errors, not terminal output)
        _subscriptions[i] = session.stdout.listen(
          (data) => _handleSessionOutput(i, data),
          onError: (error) {
            debugPrint('   ❌ Session $i error: $error');
            _eventController.add(TmuxError('Session $i error: $error'));
          },
          onDone: () {
            debugPrint('   ⚠️ Session $i closed');
            _sessions[i] = null;
          },
        );
        
        // Listen to stderr only for logging errors (don't send to terminal display)
        session.stderr.listen(
          (data) {
            final output = utf8.decode(data);
            debugPrint('   ⚠️ Session $i stderr: ${output.trim()}');
          },
          onError: (error) {
            debugPrint('   ❌ Session $i stderr error: $error');
          },
        );
        
        debugPrint('   ✅ Session $i ready');
        
        // Emit event for UI
        _eventController.add(TmuxSessionReady(i, sessionName));
        
        // Small delay between sessions
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      _isInitialized = true;
      _activeSessionIndex = 0;
      debugPrint('✅ All 3 tmux sessions initialized successfully');
      
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing tmux: $e');
      debugPrint('Stack trace: $stackTrace');
      _cleanup();
      return false;
    }
  }
  
  /// Switch to a specific session (0, 1, or 2)
  Future<bool> switchToSession(int sessionIndex) async {
    debugPrint('🔄 Switching to session $sessionIndex');
    
    if (!_isInitialized) {
      debugPrint('❌ Tmux not initialized');
      return false;
    }
    
    if (sessionIndex < 0 || sessionIndex >= 3) {
      debugPrint('❌ Invalid session index: $sessionIndex');
      return false;
    }
    
    if (_sessions[sessionIndex] == null) {
      debugPrint('❌ Session $sessionIndex not available');
      return false;
    }
    
    _activeSessionIndex = sessionIndex;
    _eventController.add(TmuxSessionSwitched(sessionIndex));
    debugPrint('✅ Switched to session $sessionIndex');
    
    return true;
  }
  
  /// Send input to the currently active session
  Future<void> sendInput(String text) async {
    if (!_isInitialized) {
      debugPrint('❌ Cannot send input: tmux not initialized');
      return;
    }
    
    final activeSession = _sessions[_activeSessionIndex];
    if (activeSession == null) {
      debugPrint('❌ Cannot send input: active session not available');
      return;
    }
    
    try {
      activeSession.write(utf8.encode(text));
    } catch (e) {
      debugPrint('❌ Error sending input to session $_activeSessionIndex: $e');
    }
  }
  
  /// Handle output from a specific session with adaptive buffering
  void _handleSessionOutput(int sessionIndex, List<int> data) {
    try {
      final output = utf8.decode(data);
      
      // Debug: Log ALL output to diagnose blank screen issue
      debugPrint('📊 Session $sessionIndex output (${output.length} chars): ${output.substring(0, output.length > 50 ? 50 : output.length)}...');
      
      // Parse terminal output for server startup messages
      if (output.contains('localhost') || output.contains('http://') || 
          output.contains('Ready') || output.contains('started')) {
        final detectedPort = SshService.parseServerPortFromOutput(output);
        if (detectedPort != null && _ref != null) {
          _ref.read(detectedServerPortProvider.notifier).state = detectedPort;
          debugPrint('🎯 Auto-detected server port from session $sessionIndex: $detectedPort');
        }
      }
      
      // Buffer the output instead of sending immediately
      _outputBuffers[sessionIndex].write(output);
      
      // Adaptive buffering: use shorter delay for initial bursts (first message),
      // longer delay for sustained streams (thinking animations)
      final now = DateTime.now();
      final timeSinceLastFlush = now.difference(_lastFlushTimes[sessionIndex]);
      final isInitialBurst = timeSinceLastFlush > _burstThreshold;
      final flushDelay = isInitialBurst ? _shortFlushDelay : _longFlushDelay;
      
      // Cancel existing flush timer and start a new one
      _flushTimers[sessionIndex]?.cancel();
      _flushTimers[sessionIndex] = Timer(flushDelay, () {
        _flushOutputBuffer(sessionIndex);
      });
      
    } catch (e) {
      debugPrint('❌ Error handling session $sessionIndex output: $e');
    }
  }
  
  /// Flush buffered output to the UI
  void _flushOutputBuffer(int sessionIndex) {
    try {
      final buffer = _outputBuffers[sessionIndex];
      if (buffer.isNotEmpty) {
        final output = buffer.toString();
        
        // Debug: Log what we're about to send to terminal display
        debugPrint('🖥️ Flushing ${output.length} chars to terminal display for session $sessionIndex');
        final preview = output.length > 80 ? output.substring(0, 80) : output;
        debugPrint('   Content: "${preview.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}${output.length > 80 ? '...' : ''}"');
        
        buffer.clear();
        
        // Update last flush time for adaptive buffering
        _lastFlushTimes[sessionIndex] = DateTime.now();
        
        // Forward batched output to UI
        _eventController.add(TmuxOutput(sessionIndex, output));
      }
    } catch (e) {
      debugPrint('❌ Error flushing output buffer for session $sessionIndex: $e');
    }
  }
  
  /// Cleanup helper
  void _cleanup() {
    for (int i = 0; i < 3; i++) {
      _subscriptions[i]?.cancel();
      _subscriptions[i] = null;
      _sessions[i]?.close();
      _sessions[i] = null;
      _flushTimers[i]?.cancel();
      _flushTimers[i] = null;
      _outputBuffers[i].clear();
    }
    _isInitialized = false;
  }
  
  void dispose() {
    debugPrint('🧹 Disposing TmuxService');
    _cleanup();
    _eventController.close();
  }
}

/// Base class for tmux events
abstract class TmuxEvent {}

/// Emitted when a session is ready
class TmuxSessionReady extends TmuxEvent {
  final int sessionIndex;
  final String sessionName;
  TmuxSessionReady(this.sessionIndex, this.sessionName);
}

/// Emitted when switching between sessions
class TmuxSessionSwitched extends TmuxEvent {
  final int sessionIndex;
  TmuxSessionSwitched(this.sessionIndex);
}

/// Emitted when output is received from a session
class TmuxOutput extends TmuxEvent {
  final int sessionIndex;
  final String output;
  TmuxOutput(this.sessionIndex, this.output);
}

/// Emitted when an error occurs
class TmuxError extends TmuxEvent {
  final String message;
  TmuxError(this.message);
}

// ============================================================================
// TERMINAL DATA MODELS
// ============================================================================

// Terminal Tab Model (backed by tmux session)
class TerminalTab {
  final String id;
  final String name;
  final Terminal terminal;
  final int sessionIndex; // 0, 1, or 2 (maps to v_session_0, v_session_1, v_session_2)
  final int terminalWidth;
  final int terminalHeight;

  TerminalTab({
    required this.id,
    required this.name,
    required this.terminal,
    required this.sessionIndex,
    this.terminalWidth = 40,
    this.terminalHeight = 50,
  });

  TerminalTab copyWith({String? name, int? terminalWidth, int? terminalHeight}) {
    return TerminalTab(
      id: id,
      name: name ?? this.name,
      terminal: terminal,
      sessionIndex: sessionIndex,
      terminalWidth: terminalWidth ?? this.terminalWidth,
      terminalHeight: terminalHeight ?? this.terminalHeight,
    );
  }
}

// Terminal State
class TerminalTabsState {
  final List<TerminalTab> tabs;
  final int activeTabIndex;
  final bool tmuxReady;
  final String? statusMessage;

  TerminalTabsState({
    required this.tabs,
    required this.activeTabIndex,
    this.tmuxReady = false,
    this.statusMessage,
  });

  TerminalTabsState copyWith({
    List<TerminalTab>? tabs,
    int? activeTabIndex,
    bool? tmuxReady,
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      tmuxReady: tmuxReady ?? this.tmuxReady,
      statusMessage: clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
    );
  }

  TerminalTab? get activeTab =>
      tabs.isNotEmpty && activeTabIndex >= 0 && activeTabIndex < tabs.length
          ? tabs[activeTabIndex]
          : null;
}

// Tmux Service Provider
final tmuxServiceProvider = Provider<TmuxService>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final tmuxService = TmuxService(sshService, ref);
  
  ref.onDispose(() {
    debugPrint('Disposing TmuxService');
    tmuxService.dispose();
  });
  
  return tmuxService;
});

// Terminal Tabs Provider (tmux-based)
final terminalTabsProvider =
    StateNotifierProvider<TerminalTabsNotifier, TerminalTabsState>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final tmuxService = ref.watch(tmuxServiceProvider);
  final notifier = TerminalTabsNotifier(sshService, tmuxService);

  // Initialize tmux when SSH connects
  ref.listen<SshService>(sshServiceProvider, (previous, next) {
    if (next.isConnected && previous != null && !previous.isConnected) {
      debugPrint('SSH connected, initializing tmux...');
      notifier.initializeTmux();
    }
  });

  return notifier;
});

// Terminal Tabs Notifier (tmux-based)
class TerminalTabsNotifier extends StateNotifier<TerminalTabsState> {
  final TmuxService _tmuxService;
  static const int maxTabs = 3;
  
  StreamSubscription? _tmuxEventsSubscription;
  bool _isInitializing = false;

  TerminalTabsNotifier(SshService sshService, this._tmuxService)
      : super(TerminalTabsState(tabs: [], activeTabIndex: -1)) {
    // Listen to tmux events with reduced debug logging
    _tmuxEventsSubscription = _tmuxService.events.listen(_handleTmuxEvent);
  }
  
  void _handleTmuxEvent(TmuxEvent event) {
    // Reduce debug spam - only log non-output events
    if (event is! TmuxOutput) {
      debugPrint('📨 Handling tmux event: ${event.runtimeType}');
    }
    
    if (event is TmuxSessionReady) {
      // Create a tab for the new session
      debugPrint('✅ Session ready: ${event.sessionName} (index: ${event.sessionIndex})');
      _createTabForSession(event.sessionIndex, event.sessionName);
    } else if (event is TmuxOutput) {
      // Find the tab for this session and update its terminal
      // Terminal writes are efficient and don't trigger rebuilds
      try {
        final tab = state.tabs.firstWhere(
          (t) => t.sessionIndex == event.sessionIndex,
        );
        
        // Debug: Log what we're writing to xterm
        debugPrint('✍️ Writing ${event.output.length} chars to xterm for session ${event.sessionIndex}');
        if (event.output.length < 100) {
          debugPrint('   Content: "${event.output.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"');
        }
        
        tab.terminal.write(event.output);
      } catch (e) {
        // Silently ignore - tab might not be created yet
      }
    } else if (event is TmuxError) {
      debugPrint('❌ tmux error event: ${event.message}');
      state = state.copyWith(statusMessage: 'Error: ${event.message}');
    }
  }

  Future<void> initializeTmux({bool forceRetry = false}) async {
    // Prevent concurrent initialization attempts
    if (_isInitializing) {
      debugPrint('⚠️ Tmux initialization already in progress, skipping duplicate request');
      return;
    }
    
    if (!forceRetry && _tmuxService.isInitialized) {
      debugPrint('✅ Tmux already initialized');
      return;
    }
    
    // Reset state for retry
    if (forceRetry) {
      debugPrint('🔄 Force retrying tmux initialization...');
      _isInitializing = false;
    }
    
    _isInitializing = true;
    state = state.copyWith(statusMessage: 'Checking for tmux...');
    debugPrint('🔍 Checking for tmux...');
    
    try {
      // Keep checking until tmux is found (with overall timeout to prevent infinite loop)
      bool tmuxInstalled = false;
      int attempt = 0;
      final startTime = DateTime.now();
      const maxDuration = Duration(minutes: 2); // Give up after 2 minutes
      
      while (!tmuxInstalled) {
        attempt++;
        
        // Check if we've exceeded the overall timeout
        if (DateTime.now().difference(startTime) > maxDuration) {
          debugPrint('⏰ Tmux detection timed out after ${maxDuration.inSeconds} seconds');
          break; // Exit loop and show requirement screen
        }
        
        if (attempt > 1) {
          debugPrint('🔄 Retry attempt $attempt for tmux detection...');
          // Wait 2 seconds between retries to avoid hammering the server
          await Future.delayed(const Duration(seconds: 2));
        }
        
        try {
          tmuxInstalled = await _tmuxService.checkTmuxInstalled()
              .timeout(const Duration(seconds: 10));
          
          if (tmuxInstalled) {
            debugPrint('✅ tmux detected after $attempt attempt(s)');
            break; // Success! Exit loop
          } else {
            // Not found, but no error - continue retrying
            debugPrint('⚠️ tmux not found, retrying...');
          }
        } catch (e) {
          debugPrint('⚠️ Tmux check attempt $attempt failed: $e');
          // Don't give up - keep trying (unless timeout reached)
        }
      }
      
      if (!tmuxInstalled) {
        // tmux not found after continuous checking - show requirement screen
        debugPrint('❌ tmux not installed (checked for ${DateTime.now().difference(startTime).inSeconds}s)');
        state = state.copyWith(
          statusMessage: 'tmux_required',
          clearStatusMessage: false,
        );
        _isInitializing = false;
        return;
      }
      
      debugPrint('✅ tmux found, initializing 3 persistent sessions...');
      state = state.copyWith(statusMessage: 'Setting up persistent terminal...');
      
      // Conservative sizing for mobile phones
      // iPhone displays roughly 40-45 characters comfortably in portrait
      // Using 40 to ensure nothing wraps or gets cut off
      const terminalWidth = 40;   // Conservative for iPhone portrait
      const terminalHeight = 50;  // Plenty of vertical space
      
      // Initialize tmux (creates/attaches to 3 sessions)
      final success = await _tmuxService.initialize(
        terminalWidth: terminalWidth,
        terminalHeight: terminalHeight,
      ).timeout(const Duration(seconds: 15));
      
      if (success) {
        debugPrint('✅ All tmux sessions initialized');
        // Tabs will be created automatically via TmuxSessionReady events
        state = state.copyWith(
          tmuxReady: true,
          statusMessage: null,
        );
      } else {
        debugPrint('❌ Failed to initialize tmux sessions');
        state = state.copyWith(
          statusMessage: 'Failed to initialize tmux. Please check your connection.',
        );
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing tmux: $e');
      debugPrint('Stack trace: $stackTrace');
      state = state.copyWith(
        statusMessage: 'Error: $e',
      );
    } finally {
      _isInitializing = false;
      debugPrint('🏁 initializeTmux finished');
    }
  }
  
  Future<void> _createTabForSession(int sessionIndex, String sessionName) async {
    final tabId = DateTime.now().millisecondsSinceEpoch.toString();
    final tabName = '${sessionIndex + 1}';
    final terminal = Terminal(maxLines: 10000);

    // Use the same terminal dimensions that were used during initialization
    // Optimized for 50% screen height terminal window
    const terminalWidth = 40;
    const terminalHeight = 50;

    final newTab = TerminalTab(
      id: tabId,
      name: tabName,
      terminal: terminal,
      sessionIndex: sessionIndex,
      terminalWidth: terminalWidth,
      terminalHeight: terminalHeight,
    );

    // Only set active tab index for the first session (session 0 = tab 1)
    // Subsequent sessions are created but not automatically selected
    final shouldSetActive = state.tabs.isEmpty;
    
    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabIndex: shouldSetActive ? 0 : null, // Stay on first tab
    );
    
    debugPrint('✅ Created tab for session $sessionIndex ($sessionName) [${terminalWidth}x$terminalHeight]${shouldSetActive ? ' (active)' : ''}');
  }

  Future<void> switchToTab(int index) async {
    debugPrint('🔄 switchToTab($index) - current: ${state.activeTabIndex}, tabs: ${state.tabs.length}');
    
    if (index < 0 || index >= state.tabs.length) {
      debugPrint('❌ Invalid tab index: $index');
      return;
    }
    
    final tab = state.tabs[index];
    
    // Switch tmux session
    await _tmuxService.switchToSession(tab.sessionIndex);
    
    // Update UI state
    state = state.copyWith(activeTabIndex: index);
    debugPrint('✅ Switched to session ${tab.sessionIndex}');
  }
  
  Future<void> resetTerminal(int sessionIndex) async {
    debugPrint('🔄 Resetting terminal session $sessionIndex...');
    
    if (sessionIndex < 0 || sessionIndex >= 3) {
      debugPrint('❌ Invalid session index: $sessionIndex');
      return;
    }
    
    try {
      final sessionName = TmuxService.sessionNames[sessionIndex];
      
      // Kill the tmux session
      debugPrint('💀 Killing tmux session: $sessionName');
      await _tmuxService._sshService.runCommandLenient('tmux kill-session -t $sessionName 2>&1');
      
      // Wait a moment for the session to fully close
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Clear the terminal display for this tab
      final tabIndex = state.tabs.indexWhere((tab) => tab.sessionIndex == sessionIndex);
      if (tabIndex >= 0) {
        final tab = state.tabs[tabIndex];
        tab.terminal.write('\x1b[2J\x1b[H'); // Clear screen and move cursor to top
        debugPrint('🧹 Cleared terminal display for tab $tabIndex');
      }
      
      // Re-create the session with current terminal dimensions
      final tab = state.tabs[tabIndex];
      debugPrint('🆕 Creating new tmux session: $sessionName (${tab.terminalWidth}x${tab.terminalHeight})');
      final session = await _tmuxService._sshService.shell(
        terminalWidth: tab.terminalWidth,
        terminalHeight: tab.terminalHeight,
      );
      if (session == null) {
        debugPrint('❌ Failed to create shell session');
        return;
      }
      
      // Start fresh tmux session
      session.write(utf8.encode('tmux new-session -s $sessionName\n'));
      
      // Update the internal sessions array
      _tmuxService._sessions[sessionIndex] = session;
      
      // Cancel old subscription
      await _tmuxService._subscriptions[sessionIndex]?.cancel();
      
      // Set up new output listener
      _tmuxService._subscriptions[sessionIndex] = session.stdout.listen(
        (data) => _tmuxService._handleSessionOutput(sessionIndex, data),
        onError: (error) {
          debugPrint('❌ Session $sessionIndex error: $error');
        },
        onDone: () {
          debugPrint('⚠️ Session $sessionIndex closed');
          _tmuxService._sessions[sessionIndex] = null;
        },
      );
      
      // Listen to stderr only for logging errors (don't send to terminal display)
      session.stderr.listen(
        (data) {
          final output = utf8.decode(data);
          debugPrint('⚠️ Session $sessionIndex stderr: ${output.trim()}');
        },
        onError: (error) {
          debugPrint('❌ Session $sessionIndex stderr error: $error');
        },
      );
      
      debugPrint('✅ Terminal session $sessionIndex reset successfully');
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error resetting terminal: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  Future<void> sendInput(String text) async {
    if (!_tmuxService.isInitialized) {
      debugPrint('❌ Cannot send input: tmux not initialized');
      return;
    }
    
    await _tmuxService.sendInput(text);
  }

  void clearStatusMessage() {
    state = state.copyWith(clearStatusMessage: true);
  }

  @override
  void dispose() {
    _tmuxEventsSubscription?.cancel();
    super.dispose();
  }
}

// Main Terminal Screen
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final FocusNode _terminalFocus = FocusNode();
  final TextEditingController _terminalController = TextEditingController();
  bool _hasText = false;
  
  bool _liquidGlassTerminalTabsShown = false;
  bool _liquidGlassTerminalInputShown = false;
  bool _nativeKeyboardVisible = false;  // Track native iOS keyboard state
  bool _isDisconnecting = false;  // Prevent multiple disconnect dialogs
  
  // Track what we've already sent to terminal for character-by-character sync
  String _lastSentText = '';
  
  // Track last tab state to avoid unnecessary updates
  int _lastActiveTabIndex = -1;
  int _lastTabCount = 0;
  
  // Custom shortcuts
  List<Map<String, String>> _customShortcuts = [];
  static const int maxCustomShortcuts = 10;
  static const String _customShortcutsKey = 'custom_terminal_shortcuts';
  
  // Server commands for web development
  static const List<Map<String, String>> _serverCommands = [
    {'command': 'npm run dev', 'description': 'Vite, Next.js, or other modern dev server'},
    {'command': 'npm start', 'description': 'Create React App or standard Node server'},
    {'command': 'python3 -m http.server 3000', 'description': 'Quick static file server on port 3000'},
    {'command': 'npx serve -s build -p 3000', 'description': 'Serve production build files'},
    {'command': 'php -S 0.0.0.0:3000', 'description': 'PHP development server'},
  ];

  @override
  void initState() {
    super.initState();
    _terminalController.addListener(_handleInputChange);
    _initLiquidGlassComponents();
    _initLiquidGlassButtons();
    _loadCustomShortcuts();
    
    // Check if SSH is already connected and initialize terminal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sshService = ref.read(sshServiceProvider);
      final tabsState = ref.read(terminalTabsProvider);
      
      debugPrint('📱 Terminal screen initialized. SSH connected: ${sshService.isConnected}, tabs: ${tabsState.tabs.length}');
      
      if (sshService.isConnected && 
          tabsState.tabs.isEmpty && 
          !tabsState.tmuxReady) {
        debugPrint('🚀 SSH already connected, initializing terminal...');
        ref.read(terminalTabsProvider.notifier).initializeTmux();
      }
    });
    
    // Tab changes are handled by Flutter UI now (state management via Riverpod)
  }
  
  Future<void> _initLiquidGlassComponents() async {
    // Initialize Liquid Glass terminal tabs (iOS 26+ only)
    await _initLiquidGlassTerminalTabs();
    
    // Initialize Liquid Glass terminal input (iOS 26+ only)
    await _initLiquidGlassTerminalInput();
  }
  
  Future<void> _initLiquidGlassTerminalTabs() async {
    final supported = await LiquidGlassTerminalTabs.isSupported();
    if (!supported) {
      debugPrint('❌ Liquid Glass terminal tabs not supported');
      return;
    }
    
    // Initialize callbacks
    await LiquidGlassTerminalTabs.initialize(
      onTabTapped: (index) {
        debugPrint('🔘 Native tab $index tapped');
        ref.read(terminalTabsProvider.notifier).switchToTab(index);
      },
      onTabLongPressed: (index) {
        debugPrint('👆 Native tab $index long pressed - resetting terminal');
        // Reset directly without Flutter confirmation (Swift already shows the context menu)
        ref.read(terminalTabsProvider.notifier).resetTerminal(index);
      },
    );
    
    // Show tabs with initial state
    final tabsState = ref.read(terminalTabsProvider);
    await LiquidGlassTerminalTabs.show(
      activeTab: tabsState.activeTabIndex >= 0 ? tabsState.activeTabIndex : 0,
      tabCount: tabsState.tabs.length,
    );
    
    setState(() {
      _liquidGlassTerminalTabsShown = true;
    });
    
    debugPrint('✅ Liquid Glass terminal tabs initialized');
  }
  
  Future<void> _initLiquidGlassTerminalInput() async {
    // Initialize callbacks
    await LiquidGlassTerminalInput.initialize(
      onCommandSent: (text) {
        // Text has already been typed character-by-character into terminal
        // Just send the enter key to submit it
        ref.read(terminalTabsProvider.notifier).sendInput('\r');
        
        // Clear the input after sending
        _terminalController.clear();
        _lastSentText = ''; // Reset tracking
        setState(() {
          _hasText = false;
        });
      },
      onInputChanged: (text) {
        // Sync text from native to Flutter controller
        if (_terminalController.text != text) {
          _terminalController.text = text;
          setState(() {
            _hasText = text.trim().isNotEmpty;
          });
          // Send the diff to terminal (character-by-character)
          _syncTextToTerminal(text);
        }
      },
      onDismissKeyboard: () {
        // Unfocus Flutter side
        FocusScope.of(context).unfocus();
      },
      onKeyboardShow: () {
        // Native keyboard opened
        if (mounted) {
          setState(() {
            _nativeKeyboardVisible = true;
          });
        }
      },
      onKeyboardHide: () {
        // Native keyboard closed
        if (mounted) {
          setState(() {
            _nativeKeyboardVisible = false;
          });
        }
      },
    );
    
    // Show the input
    final shown = await LiquidGlassTerminalInput.show(
      placeholder: 'Type command...',
    );
    
    if (shown && mounted) {
      setState(() {
        _liquidGlassTerminalInputShown = true;
      });
      debugPrint('✅ Liquid Glass terminal input shown');
    }
  }
  
  // Removed: _updateLiquidGlassTabBar - now using Flutter UI for tabs
  
  Future<void> _initLiquidGlassButtons() async {
    // Initialize Power button
    await _initLiquidGlassPowerButton();
    
    // Initialize Info button
    await _initLiquidGlassInfoButton();
    
    // Initialize Play button
    await _initLiquidGlassPlayButton();
  }
  
  Future<void> _initLiquidGlassPowerButton() async {
    // Set up callback for power button taps (disconnect from terminal)
    LiquidGlassPowerButton.setOnPowerButtonTappedCallback(() {
      _handlePowerButtonTap();
    });
    
    // Show the power button in connected state (blue)
    await LiquidGlassPowerButton.show(isConnected: true);
  }
  
  Future<void> _initLiquidGlassInfoButton() async {
    // Info button handles sheet natively in Swift - no callback needed
    // Just show the button
    await LiquidGlassInfoButton.show();
  }
  
  Future<void> _initLiquidGlassPlayButton() async {
    // Set up callback for play button taps (server detection & preview)
    LiquidGlassPlayButton.setOnPlayButtonTappedCallback(() {
      _handlePlayButtonTap();
    });
    
    // Show the play button
    await LiquidGlassPlayButton.show(isLoading: false);
  }
  
  void _handlePlayButtonTap() async {
    debugPrint('▶️ Play button tapped - checking for running server');
    
    // Update button to loading state
    await LiquidGlassPlayButton.updateState(isLoading: true);
    
    // Strategy: Try terminal output first (most accurate), then scan
    int? detectedPort = ref.read(detectedServerPortProvider);
    debugPrint('🔍 Port from terminal output: $detectedPort');
    
    // If no port from terminal output, scan for running servers
    if (detectedPort == null) {
      debugPrint('🔍 No port from terminal output, scanning...');
      final sshService = ref.read(sshServiceProvider.notifier);
      detectedPort = await sshService.detectRunningServer();
      debugPrint('🔍 Port from scan: $detectedPort');
      
      // Save the detected port for next time
      if (detectedPort != null) {
        ref.read(detectedServerPortProvider.notifier).state = detectedPort;
      }
    } else {
      debugPrint('✅ Using port from terminal output: $detectedPort');
      
      // Verify this port is actually still open before using it
      final sshService = ref.read(sshServiceProvider);
      final stillOpen = await sshService.checkSpecificPort(detectedPort);
      
      if (!stillOpen) {
        debugPrint('⚠️ Port $detectedPort from terminal is no longer open, scanning...');
        detectedPort = await sshService.detectRunningServer();
        debugPrint('🔍 Port from scan: $detectedPort');
        
        if (detectedPort != null) {
          ref.read(detectedServerPortProvider.notifier).state = detectedPort;
        }
      }
    }
    
    // Reset button state
    await LiquidGlassPlayButton.updateState(isLoading: false);
    
    if (detectedPort == null) {
      // No server detected - show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No server detected. Start your dev server in the terminal to preview.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 200,
              left: 20,
              right: 20,
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    // Server detected - get host IP and navigate to preview
    final hostIp = ref.read(sshServiceProvider).hostIp;
    if (hostIp == null) {
      debugPrint('❌ Host IP is null');
      return;
    }
    
    final previewUrl = 'http://$hostIp:$detectedPort';
    debugPrint('✅ Opening preview: $previewUrl');
    
    // Hide terminal UI before navigating
    if (_liquidGlassTerminalTabsShown) {
      await LiquidGlassTerminalTabs.hide();
    }
    if (_liquidGlassTerminalInputShown) {
      await LiquidGlassTerminalInput.hide();
    }
    await LiquidGlassPowerButton.hide();
    await LiquidGlassInfoButton.hide();
    await LiquidGlassPlayButton.hide();
    
    // Navigate to WebPreview screen
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WebPreviewScreen(
            url: previewUrl,
            hostIp: hostIp,
          ),
        ),
      );
      
      // When returning from Preview, restore terminal UI elements
      if (mounted) {
        await LiquidGlassPowerButton.show(isConnected: true);
        await LiquidGlassInfoButton.show();
        await LiquidGlassPlayButton.show(isLoading: false);
        if (_liquidGlassTerminalTabsShown) {
          final tabsState = ref.read(terminalTabsProvider);
          await LiquidGlassTerminalTabs.show(
            activeTab: tabsState.activeTabIndex >= 0 ? tabsState.activeTabIndex : 0,
            tabCount: tabsState.tabs.length,
          );
        }
        if (_liquidGlassTerminalInputShown) {
          await LiquidGlassTerminalInput.show(placeholder: 'Type command...');
        }
      }
    }
  }
  
  void _handlePowerButtonTap() {
    // Prevent multiple dialogs
    if (_isDisconnecting) return;
    
    _isDisconnecting = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'End session?',
          style: TextStyle(color: Colors.white, fontSize: 20),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.pop(context);
              _isDisconnecting = false;
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          IconButton(
            onPressed: () async {
              Navigator.pop(context);
              await _disconnect();
              _isDisconnecting = false;
            },
            icon: const Icon(Icons.check, color: Colors.white),
          ),
        ],
      ),
    ).then((_) {
      // Ensure flag is reset even if dialog is dismissed other ways
      _isDisconnecting = false;
    });
  }
  
  Future<void> _disconnect() async {
    try {
      await ref.read(sshServiceProvider.notifier).disconnect();
      
      // Clear connection state
      ref.read(connectedIpProvider.notifier).state = null;
      ref.read(connectedUsernameProvider.notifier).state = null;
      
      // Update power button state to disconnected before navigating back
      await LiquidGlassPowerButton.updateState(isConnected: false);
      
      // Navigate back to SSH screen (buttons will remain visible)
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error disconnecting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    _terminalController.dispose();
    
    // Hide native components
    if (_liquidGlassTerminalTabsShown) {
      LiquidGlassTerminalTabs.hide();
    }
    if (_liquidGlassTerminalInputShown) {
      LiquidGlassTerminalInput.hide();
    }
    
    // Keep Power, Info, and Play buttons visible - they persist across SSH/Terminal screens
    // They will be managed by the SSH screen when we navigate back
    
    super.dispose();
  }

  void _handleInputChange() {
    final current = _terminalController.text;

    // Update button state
    final hasText = current.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }

    // Sync to Liquid Glass input if active
    if (_liquidGlassTerminalInputShown) {
      LiquidGlassTerminalInput.setText(current);
    }

    // Sync character-by-character to terminal
    _syncTextToTerminal(current);
  }
  
  /// Sync text to terminal character-by-character
  /// Only sends the difference between what's typed and what's already been sent
  void _syncTextToTerminal(String currentText) {
    // If text is shorter (user deleted), we can't unsend characters
    // So we need to handle backspace specially
    if (currentText.length < _lastSentText.length) {
      // User deleted characters - send backspace
      final numDeleted = _lastSentText.length - currentText.length;
      for (int i = 0; i < numDeleted; i++) {
        ref.read(terminalTabsProvider.notifier).sendInput('\x7f'); // Backspace (DEL)
      }
      _lastSentText = currentText;
    } else if (currentText.length > _lastSentText.length) {
      // User added characters - send the new characters
      final newChars = currentText.substring(_lastSentText.length);
      
      // Debug: Log what we're sending
      debugPrint('📝 Sending to terminal: "$newChars" (length: ${newChars.length})');
      
      ref.read(terminalTabsProvider.notifier).sendInput(newChars);
      _lastSentText = currentText;
    }
    // If lengths are equal, text is the same (no change)
  }

  Future<void> _loadCustomShortcuts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? shortcutsJson = prefs.getString(_customShortcutsKey);
      if (shortcutsJson != null && shortcutsJson.isNotEmpty) {
        final decoded = jsonDecode(shortcutsJson);
        if (decoded is List) {
          setState(() {
            _customShortcuts = List<Map<String, String>>.from(
              decoded.map((item) => Map<String, String>.from(item as Map))
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading custom shortcuts: $e');
      // Reset to empty if corrupted
      setState(() {
        _customShortcuts = [];
      });
    }
  }

  Future<void> _saveCustomShortcuts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customShortcutsKey, jsonEncode(_customShortcuts));
    } catch (e) {
      debugPrint('Error saving custom shortcuts: $e');
    }
  }

  void _sendCommand(String command) {
    ref.read(terminalTabsProvider.notifier).sendInput('$command\r');
  }

  void _sendKeys(String sequence) {
    ref.read(terminalTabsProvider.notifier).sendInput(sequence);
  }

  @override
  Widget build(BuildContext context) {
    final sshService = ref.watch(sshServiceProvider);
    final tabsState = ref.watch(terminalTabsProvider);
    final activeTab = tabsState.activeTab;

    if (!sshService.isConnected) {
      return Container(
        color: const Color(0xFF0a0a0a),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Text(
              'Connect to your server to use terminal',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ),
        ),
      );
    }

    // Show tmux requirement screen if tmux not installed
    if (tabsState.statusMessage == 'tmux_required') {
      return _buildTmuxRequirementScreen();
    }

    // Show loading while initializing
    if (!tabsState.tmuxReady && activeTab == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
            const SizedBox(height: 16),
            Text(
              tabsState.statusMessage ?? 'Setting up terminal...',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Error state
    if (activeTab == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Terminal not ready',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              tabsState.statusMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Tab bar updates are automatic via Flutter state management (Riverpod)

    // Update native tabs ONLY when tab state actually changes
    if (_liquidGlassTerminalTabsShown) {
      final currentActiveTab = tabsState.activeTabIndex >= 0 ? tabsState.activeTabIndex : 0;
      final currentTabCount = tabsState.tabs.length;
      
      if (currentActiveTab != _lastActiveTabIndex || currentTabCount != _lastTabCount) {
        _lastActiveTabIndex = currentActiveTab;
        _lastTabCount = currentTabCount;
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          LiquidGlassTerminalTabs.updateTabs(
            activeTab: currentActiveTab,
            tabCount: currentTabCount,
          );
        });
      }
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Native tabs are shown via Swift/iOS - no Flutter tab bar needed
            // Add spacing where native tabs appear
            if (_liquidGlassTerminalTabsShown)
              const SizedBox(height: 64), // Space for native tab bar
            
            // Terminal display - back to full height for Qwen UI
            Expanded(
              child: Container(
                color: const Color(0xFF0a0a0a), // Match app background
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _terminalFocus.requestFocus();
                      },
                      child: TerminalView(
                        activeTab.terminal,
                        padding: const EdgeInsets.all(8),
                        backgroundOpacity: 0, // Make xterm background transparent
                        textStyle: const TerminalStyle(fontSize: 14), // Larger font for mobile
                      ),
                    ),
                    // Invisible text field for input
                    Positioned(
                      left: -1000,
                      top: -1000,
                      width: 1,
                      height: 1,
                      child: TextField(
                        controller: _terminalController,
                        focusNode: _terminalFocus,
                        autofocus: false,
                        style: const TextStyle(color: Colors.transparent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                        ),
                        keyboardType: TextInputType.text,
                        // Use newline action on iOS, none on other platforms
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Keyboard shortcuts - sits directly above terminal input
            Padding(
              padding: EdgeInsets.only(
                bottom: _liquidGlassTerminalInputShown 
                  ? (_nativeKeyboardVisible ? 52 : 52)  // Always 52px above input (8px safe area bottom + 44px input height)
                  : 0,
              ),
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildShortcutButton('tab', '\t'),
                      _buildShortcutButton('esc', '\x1b'),
                      _buildShortcutButton('ctrl', 'ctrl'), // Special handling for ctrl combinations
                      _buildShortcutButton('↑', '\x1b[A'),
                      _buildShortcutButton('↓', '\x1b[B'),
                      _buildShortcutButton('←', '\x1b[D'),
                      _buildShortcutButton('→', '\x1b[C'),
                      _buildServerButton(),
                      _buildBackupButton(),
                      _buildCustomButton('cstm'),
                    ],
                  ),
                ),
              ),
            ),

            // Terminal input bar - only show if Liquid Glass is not supported
            if (!_liquidGlassTerminalInputShown)
              Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 
                _terminalFocus.hasFocus 
                  ? 0  // No padding when keyboard is open
                  : 50 // Extra padding when keyboard is closed (clears nav bar)
              ),
              child: Container(
                width: double.infinity,
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: TextField(
                  controller: _terminalController,
                  focusNode: _terminalFocus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type commands here...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 16),
                    filled: true,
                    fillColor: Colors.black,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(
                        color: Colors.white.withAlpha(51),
                        width: 1.2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(
                        color: Colors.white.withAlpha(51),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(
                        color: Colors.white.withAlpha(102),
                        width: 1.8,
                      ),
                    ),
                    prefixIcon: IconButton(
                      icon: const Icon(
                        CupertinoIcons.keyboard_chevron_compact_down,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                      },
                      splashRadius: 20,
                    ),
                    suffixIcon: Container(
                      margin: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hasText 
                              ? Colors.blue
                              : Colors.grey.withAlpha(77),
                          ),
                          child: Icon(
                            CupertinoIcons.arrow_up,
                            color: _hasText 
                              ? Colors.white
                              : Colors.grey.withAlpha(153),
                            size: 20,
                          ),
                        ),
                        onPressed: _hasText
                          ? () {
                              _sendCommand('\r');
                              _terminalController.clear();
                              setState(() {
                                _hasText = false;
                              });
                              FocusScope.of(context).unfocus();
                            }
                          : null,
                        splashRadius: 24,
                      ),
                    ),
                  ),
                  onSubmitted: (value) {
                    _sendCommand('\r');
                    _terminalController.clear();
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTmuxRequirementScreen() {
    return Container(
      color: const Color(0xFF0a0a0a),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                const Icon(
                  CupertinoIcons.square_stack_3d_up,
                  color: Colors.blue,
                  size: 64,
                ),
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'tmux Required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Description
                const Text(
                  'This app uses tmux for persistent terminal sessions.\n\n'
                  'Install tmux on your server to continue:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Install commands - simplified to Mac and Linux
                _buildInstallCommand('macOS', 'brew install tmux'),
                _buildInstallCommand('Linux', 'sudo apt install tmux'),
                const SizedBox(height: 8),
                Text(
                  'Other distributions: yum, dnf, pacman, etc.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // Retry button - now continuously checks until tmux is found
                ElevatedButton(
                  onPressed: () async {
                    // Start continuous checking
                    final notifier = ref.read(terminalTabsProvider.notifier);
                    await notifier.initializeTmux(forceRetry: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: const Text(
                    'Retry Connection',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Install tmux and click Retry',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildInstallCommand(String os, String command) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            os,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha:0.1)),
            ),
            child: Text(
              command,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutButton(String text, String sequence, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () {
            // Special handling for Ctrl key
            if (sequence == 'ctrl') {
              _showCtrlMenu();
            } else {
              _sendKeys(sequence);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.blue[700],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1a1a1a),
                title: const Text(
                  'Start Web Server',
                  style: TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _serverCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = _serverCommands[index];
                      return ListTile(
                        title: Text(
                          cmd['command']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                        ),
                        subtitle: Text(
                          cmd['description']!,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendCommand(cmd['command']!);
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'srvr',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupButton() {
    // Common backup/utility commands
    final backupCommands = [
      {'command': 'tar -czf backup.tar.gz .', 'description': 'Backup current directory'},
      {'command': 'git add . && git commit -m "checkpoint"', 'description': 'Git checkpoint'},
      {'command': 'npm run build', 'description': 'Build project'},
      {'command': 'docker-compose up -d', 'description': 'Start Docker containers'},
      {'command': 'pm2 restart all', 'description': 'Restart PM2 processes'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.green[700],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1a1a1a),
                title: const Text(
                  'Quick Commands',
                  style: TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: backupCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = backupCommands[index];
                      return ListTile(
                        title: Text(
                          cmd['command']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          cmd['description']!,
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendCommand(cmd['command']!);
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'bkup',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCtrlMenu() {
    final ctrlCommands = [
      {'key': 'Ctrl+C', 'sequence': '\x03', 'description': 'Interrupt (cancel current process)'},
      {'key': 'Ctrl+D', 'sequence': '\x04', 'description': 'EOF (exit shell or end input)'},
      {'key': 'Ctrl+Z', 'sequence': '\x1a', 'description': 'Suspend process (send to background)'},
      {'key': 'Ctrl+L', 'sequence': '\x0c', 'description': 'Clear screen'},
      {'key': 'Ctrl+A', 'sequence': '\x01', 'description': 'Move cursor to beginning of line'},
      {'key': 'Ctrl+E', 'sequence': '\x05', 'description': 'Move cursor to end of line'},
      {'key': 'Ctrl+U', 'sequence': '\x15', 'description': 'Delete from cursor to start of line'},
      {'key': 'Ctrl+K', 'sequence': '\x0b', 'description': 'Delete from cursor to end of line'},
      {'key': 'Ctrl+W', 'sequence': '\x17', 'description': 'Delete word before cursor'},
      {'key': 'Ctrl+R', 'sequence': '\x12', 'description': 'Reverse search command history'},
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text(
          'Ctrl Shortcuts',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tap to send control sequence',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ctrlCommands.length,
                  itemBuilder: (context, index) {
                    final cmd = ctrlCommands[index];
                    return ListTile(
                      title: Text(
                        cmd['key']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        cmd['description']!,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _sendKeys(cmd['sequence']!);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomButton(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show custom shortcuts dialog
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1a1a1a),
                title: const Text(
                  'Custom Shortcuts',
                  style: TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._customShortcuts.map((shortcut) => ListTile(
                        title: Text(
                          shortcut['title']!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          shortcut['command']!,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _customShortcuts.remove(shortcut);
                            });
                            _saveCustomShortcuts();
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendCommand(shortcut['command']!);
                        },
                      )),
                      if (_customShortcuts.length < maxCustomShortcuts)
                        ListTile(
                          leading: const Icon(Icons.add, color: Colors.blue),
                          title: const Text(
                            'Add Custom Shortcut',
                            style: TextStyle(color: Colors.blue),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showAddShortcutDialog();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddShortcutDialog() {
    final titleController = TextEditingController();
    final commandController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text(
          'New Custom Shortcut',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: TextStyle(color: Colors.grey[400]),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commandController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Command',
                labelStyle: TextStyle(color: Colors.grey[400]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  commandController.text.isNotEmpty) {
                setState(() {
                  _customShortcuts.add({
                    'title': titleController.text,
                    'command': commandController.text,
                  });
                });
                _saveCustomShortcuts();
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
