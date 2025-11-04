import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ssh.dart';

/// TmuxService manages a single SSH connection with tmux multiplexing
/// This provides persistent sessions that survive app disconnection
class TmuxService {
  final SshService _sshService;
  dartssh2.SSHSession? _tmuxSession;
  StreamSubscription? _stdoutSubscription;
  
  bool _isInitialized = false;
  bool _tmuxAvailable = false;
  String? _sessionName;
  String? _tmuxPath; // Store the full path to tmux
  
  final Map<int, TmuxWindow> _windows = {};
  int _nextWindowId = 0;
  int _activeWindowId = -1;
  
  final StreamController<TmuxEvent> _eventController = StreamController.broadcast();
  Stream<TmuxEvent> get events => _eventController.stream;
  
  TmuxService(this._sshService);
  
  bool get isInitialized => _isInitialized;
  bool get tmuxAvailable => _tmuxAvailable;
  String? get sessionName => _sessionName;
  int get activeWindowId => _activeWindowId;
  List<TmuxWindow> get windows => _windows.values.toList();
  
  static const String _tmuxPathKey = 'tmux_path';
  static const String _tmuxAvailableKey = 'tmux_available';
  
  /// Load cached tmux info from previous session
  Future<void> loadCachedTmuxInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedPath = prefs.getString(_tmuxPathKey);
      final cachedAvailable = prefs.getBool(_tmuxAvailableKey) ?? false;
      
      if (cachedAvailable && cachedPath != null) {
        _tmuxPath = cachedPath;
        _tmuxAvailable = true;
        debugPrint('📦 Loaded cached tmux info: path=$cachedPath, available=$cachedAvailable');
      }
    } catch (e) {
      debugPrint('Error loading cached tmux info: $e');
    }
  }
  
  /// Save tmux info for next session
  Future<void> _saveTmuxInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_tmuxAvailable && _tmuxPath != null) {
        await prefs.setString(_tmuxPathKey, _tmuxPath!);
        await prefs.setBool(_tmuxAvailableKey, true);
        debugPrint('💾 Saved tmux info: path=$_tmuxPath');
      }
    } catch (e) {
      debugPrint('Error saving tmux info: $e');
    }
  }
  
  /// Check if tmux is installed (does not auto-install)
  Future<TmuxCheckResult> checkTmuxInstalled() async {
    if (!_sshService.isConnected) {
      debugPrint('Cannot check tmux: not connected');
      return TmuxCheckResult.notConnected;
    }
    
    // First try cached info if available
    if (_tmuxAvailable && _tmuxPath != null) {
      debugPrint('🚀 Using cached tmux path: $_tmuxPath');
      // Quick verify it still exists
      final testResult = await _sshService.runCommandLenient('test -x $_tmuxPath && echo "ok"');
      if (testResult != null && testResult.trim() == 'ok') {
        debugPrint('✅ Cached tmux path still valid');
        return TmuxCheckResult.installed;
      } else {
        debugPrint('⚠️ Cached tmux path no longer valid, re-detecting...');
        _tmuxAvailable = false;
        _tmuxPath = null;
      }
    }
    
    try {
      // Check if tmux is already installed - try multiple methods
      debugPrint('Checking if tmux is installed...');
      
      // Try 1: which tmux
      var checkResult = await _sshService.runCommandLenient('which tmux');
      debugPrint('which tmux result: ${checkResult?.trim() ?? "empty"}');
      
      // Try 2: command -v tmux (more reliable)
      if (checkResult == null || checkResult.trim().isEmpty || checkResult.toLowerCase().contains('not found')) {
        debugPrint('Trying command -v tmux...');
        checkResult = await _sshService.runCommandLenient('command -v tmux');
        debugPrint('command -v tmux result: ${checkResult?.trim() ?? "empty"}');
      }
      
      // Try 3: Check common Homebrew paths on macOS
      if (checkResult == null || checkResult.trim().isEmpty || checkResult.toLowerCase().contains('not found')) {
        debugPrint('Checking common Homebrew paths...');
        final brewPaths = [
          '/opt/homebrew/bin/tmux',  // Apple Silicon Macs
          '/usr/local/bin/tmux',     // Intel Macs
          '/usr/bin/tmux',           // Linux default
        ];
        
        for (final path in brewPaths) {
          final testResult = await _sshService.runCommandLenient('test -x $path && echo "found:$path"');
          debugPrint('Testing $path: ${testResult?.trim() ?? "empty"}');
          if (testResult != null && testResult.contains('found:')) {
            checkResult = path;
            debugPrint('✅ Found tmux at: $path');
            break;
          }
        }
      }
      
      // Check if we got a valid path (starts with /)
      if (checkResult != null && 
          checkResult.trim().isNotEmpty && 
          checkResult.trim().startsWith('/') &&
          !checkResult.toLowerCase().contains('not found')) {
        _tmuxPath = checkResult.trim();
        debugPrint('✅ tmux is available at: $_tmuxPath');
        _tmuxAvailable = true;
        await _saveTmuxInfo(); // Persist for next session
        return TmuxCheckResult.installed;
      }
      
      debugPrint('❌ tmux not found on server after all checks');
      
      // Detect OS to provide install command
      final osInfo = await _sshService.runCommandLenient('cat /etc/os-release || uname -s');
      debugPrint('OS Info: $osInfo');
      
      if (osInfo != null) {
        final os = osInfo.toLowerCase();
        if (os.contains('ubuntu') || os.contains('debian')) {
          return TmuxCheckResult.notInstalledUbuntu;
        } else if (os.contains('centos') || os.contains('rhel') || os.contains('fedora')) {
          return TmuxCheckResult.notInstalledCentos;
        } else if (os.contains('darwin') || os.contains('macos')) {
          return TmuxCheckResult.notInstalledMac;
        } else if (os.contains('arch')) {
          return TmuxCheckResult.notInstalledArch;
        }
      }
      
      return TmuxCheckResult.notInstalledUnknown;
      
    } catch (e) {
      debugPrint('Error checking tmux: $e');
      return TmuxCheckResult.error;
    }
  }
  
  /// Install tmux on the server (requires user consent)
  Future<bool> installTmux(TmuxCheckResult osType) async {
    if (!_sshService.isConnected) {
      debugPrint('Cannot install tmux: not connected');
      return false;
    }
    
    String? installCommand;
    
    switch (osType) {
      case TmuxCheckResult.notInstalledUbuntu:
        installCommand = 'sudo apt-get update && sudo apt-get install -y tmux';
        break;
      case TmuxCheckResult.notInstalledCentos:
        installCommand = 'sudo yum install -y tmux';
        break;
      case TmuxCheckResult.notInstalledMac:
        installCommand = 'brew install tmux';
        break;
      case TmuxCheckResult.notInstalledArch:
        installCommand = 'sudo pacman -S --noconfirm tmux';
        break;
      default:
        debugPrint('Cannot determine install command for OS');
        return false;
    }
    
    try {
      debugPrint('Installing tmux with: $installCommand');
      await _sshService.runCommandLenient(installCommand);
      
      // Verify installation
      final verifyResult = await _sshService.runCommandLenient('which tmux');
      if (verifyResult != null && verifyResult.trim().isNotEmpty) {
        debugPrint('✅ tmux installed successfully');
        _tmuxAvailable = true;
        return true;
      }
      
      debugPrint('⚠️ tmux installation verification failed');
      return false;
      
    } catch (e) {
      debugPrint('Error installing tmux: $e');
      return false;
    }
  }
  
  /// Initialize tmux control mode (assumes tmux is already installed/checked)
  Future<bool> initialize() async {
    if (_isInitialized) {
      debugPrint('tmux already initialized');
      return true;
    }
    
    if (!_sshService.isConnected) {
      debugPrint('Cannot initialize tmux: not connected');
      return false;
    }
    
    if (!_tmuxAvailable) {
      debugPrint('Cannot initialize: tmux not available');
      return false;
    }
    
    try {
      debugPrint('🚀 Starting tmux control mode...');
      
      // Generate unique session name
      _sessionName = 'v_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('📝 Session name: $_sessionName');
      
      // Start a shell session
      debugPrint('📤 Opening shell session...');
      _tmuxSession = await _sshService.shell();
      
      if (_tmuxSession == null) {
        debugPrint('❌ Failed to create shell session');
        return false;
      }
      
      debugPrint('✅ Shell session created');
      
      // Listen to tmux output
      _stdoutSubscription = _tmuxSession!.stdout.listen(
        _handleTmuxOutput,
        onError: (error) {
          debugPrint('❌ tmux session error: $error');
          _handleError(error);
        },
        onDone: () {
          debugPrint('⚠️ tmux session closed');
          _isInitialized = false;
        },
      );
      
      debugPrint('✅ Output listener attached');
      
      // Use full path to tmux if available, otherwise rely on PATH
      final tmuxCommand = _tmuxPath ?? 'tmux';
      
      // Start tmux in NORMAL mode (not control mode -C)
      // We're using xterm.js which handles all the terminal emulation
      // Control mode adds complexity we don't need
      debugPrint('📤 Sending: $tmuxCommand new-session -s $_sessionName');
      _tmuxSession!.write(utf8.encode('$tmuxCommand new-session -s $_sessionName\n'));
      
      // Wait a bit for tmux to start
      debugPrint('⏳ Waiting for tmux to start...');
      await Future.delayed(const Duration(milliseconds: 1000));
      
      _isInitialized = true;
      debugPrint('✅ tmux control mode initialized with session: $_sessionName');
      
      // tmux automatically creates first window (window 0) when session starts
      // Let's register it manually
      final firstWindow = TmuxWindow(id: 0, name: '1');
      _windows[0] = firstWindow;
      _activeWindowId = 0;
      _nextWindowId = 1;
      
      debugPrint('✅ Registered first tmux window (id: 0)');
      _eventController.add(TmuxWindowCreated(firstWindow));
      
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing tmux: $e');
      debugPrint('Stack trace: $stackTrace');
      _isInitialized = false;
      return false;
    }
  }
  
  /// Create a new tmux window (equivalent to a terminal tab)
  Future<int?> createWindow() async {
    if (!_isInitialized) {
      debugPrint('Cannot create window: tmux not initialized');
      return null;
    }
    
    try {
      final windowId = _nextWindowId++;
      
      // Create new window in tmux
      await _sendCommand('new-window');
      
      final window = TmuxWindow(
        id: windowId,
        name: '${windowId + 1}',
      );
      
      _windows[windowId] = window;
      _activeWindowId = windowId;
      
      _eventController.add(TmuxWindowCreated(window));
      
      debugPrint('Created tmux window $windowId');
      return windowId;
      
    } catch (e) {
      debugPrint('Error creating window: $e');
      return null;
    }
  }
  
  /// Switch to a specific window
  Future<bool> switchToWindow(int windowId) async {
    if (!_isInitialized) return false;
    if (!_windows.containsKey(windowId)) return false;
    
    try {
      // tmux windows are 0-indexed
      await _sendCommand('select-window -t $windowId');
      _activeWindowId = windowId;
      
      _eventController.add(TmuxWindowSwitched(windowId));
      
      debugPrint('Switched to window $windowId');
      return true;
      
    } catch (e) {
      debugPrint('Error switching window: $e');
      return false;
    }
  }
  
  /// Close a specific window
  Future<bool> closeWindow(int windowId) async {
    if (!_isInitialized) return false;
    if (!_windows.containsKey(windowId)) return false;
    if (_windows.length <= 1) {
      debugPrint('Cannot close last window');
      return false;
    }
    
    try {
      await _sendCommand('kill-window -t $windowId');
      _windows.remove(windowId);
      
      // Switch to another window if this was active
      if (_activeWindowId == windowId) {
        _activeWindowId = _windows.keys.first;
        await switchToWindow(_activeWindowId);
      }
      
      _eventController.add(TmuxWindowClosed(windowId));
      
      debugPrint('Closed window $windowId');
      return true;
      
    } catch (e) {
      debugPrint('Error closing window: $e');
      return false;
    }
  }
  
  /// Send input to the active window
  Future<void> sendInput(String text) async {
    if (!_isInitialized || _tmuxSession == null) {
      debugPrint('Cannot send input: tmux not initialized');
      return;
    }
    
    try {
      // In tmux control mode, we send keys directly
      _tmuxSession!.write(utf8.encode(text));
    } catch (e) {
      debugPrint('Error sending input: $e');
    }
  }
  
  /// Send a tmux command
  Future<void> _sendCommand(String command) async {
    if (_tmuxSession == null) return;
    
    debugPrint('Sending tmux command: $command');
    _tmuxSession!.write(utf8.encode('$command\n'));
  }
  
  /// Handle output from tmux (normal mode)
  void _handleTmuxOutput(List<int> data) {
    try {
      final output = utf8.decode(data);
      
      // In normal tmux mode, we get raw terminal output
      // Just forward it directly to the active window's terminal
      // xterm.js will handle all the rendering
      
      if (_activeWindowId >= 0 && _windows.containsKey(_activeWindowId)) {
        _eventController.add(TmuxOutput(_activeWindowId, output));
      }
    } catch (e) {
      debugPrint('❌ Error handling tmux output: $e');
    }
  }
  
  void _handleError(dynamic error) {
    _eventController.add(TmuxError(error.toString()));
  }
  
  /// Detach from tmux session (keeps it running on server)
  Future<void> detach() async {
    if (!_isInitialized) return;
    
    try {
      debugPrint('Detaching from tmux session $_sessionName');
      await _sendCommand('detach');
      
      _stdoutSubscription?.cancel();
      _tmuxSession?.close();
      _tmuxSession = null;
      _isInitialized = false;
      
    } catch (e) {
      debugPrint('Error detaching from tmux: $e');
    }
  }
  
  /// Reattach to existing tmux session
  Future<bool> reattach() async {
    if (_sessionName == null) return false;
    
    try {
      debugPrint('Reattaching to tmux session $_sessionName');
      
      // Check if session still exists
      final sessions = await _sshService.runCommandLenient('tmux list-sessions');
      if (sessions == null || !sessions.contains(_sessionName!)) {
        debugPrint('Session $_sessionName no longer exists');
        return false;
      }
      
      // Reconnect to existing session
      _tmuxSession = await _sshService.shell();
      if (_tmuxSession == null) return false;
      
      _stdoutSubscription = _tmuxSession!.stdout.listen(
        _handleTmuxOutput,
        onError: _handleError,
        onDone: () => _isInitialized = false,
      );
      
      await _sendCommand('tmux -C attach-session -t $_sessionName');
      await Future.delayed(const Duration(milliseconds: 500));
      
      _isInitialized = true;
      debugPrint('✅ Reattached to tmux session $_sessionName');
      
      return true;
      
    } catch (e) {
      debugPrint('Error reattaching to tmux: $e');
      return false;
    }
  }
  
  /// Kill the tmux session (destroys all windows)
  Future<void> killSession() async {
    if (_sessionName == null) return;
    
    try {
      debugPrint('Killing tmux session $_sessionName');
      await _sshService.runCommandLenient('tmux kill-session -t $_sessionName');
      
      _windows.clear();
      _activeWindowId = -1;
      _sessionName = null;
      _isInitialized = false;
      
    } catch (e) {
      debugPrint('Error killing tmux session: $e');
    }
  }
  
  void dispose() {
    debugPrint('Disposing TmuxService');
    _stdoutSubscription?.cancel();
    _tmuxSession?.close();
    _eventController.close();
  }
}

/// Represents a tmux window (equivalent to a terminal tab)
class TmuxWindow {
  final int id;
  final String name;
  
  TmuxWindow({
    required this.id,
    required this.name,
  });
}

/// Base class for tmux events
abstract class TmuxEvent {}

class TmuxWindowCreated extends TmuxEvent {
  final TmuxWindow window;
  TmuxWindowCreated(this.window);
}

class TmuxWindowClosed extends TmuxEvent {
  final int windowId;
  TmuxWindowClosed(this.windowId);
}

class TmuxWindowSwitched extends TmuxEvent {
  final int windowId;
  TmuxWindowSwitched(this.windowId);
}

class TmuxOutput extends TmuxEvent {
  final int windowId;
  final String output;
  TmuxOutput(this.windowId, this.output);
}

class TmuxError extends TmuxEvent {
  final String message;
  TmuxError(this.message);
}

/// Result of checking tmux installation status
enum TmuxCheckResult {
  installed,
  notInstalledUbuntu,
  notInstalledCentos,
  notInstalledMac,
  notInstalledArch,
  notInstalledUnknown,
  notConnected,
  error,
}

