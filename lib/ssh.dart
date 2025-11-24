import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'terminal.dart';
import 'preview.dart';

// ============================================================================
// LIQUID GLASS - SSH Components (Native iOS)
// ============================================================================

/// Toast notification (bottom)
class LiquidGlassToast {
  static const MethodChannel _channel = MethodChannel('liquid_glass_toast');
  
  static Future<bool> show({
    required String message,
    String style = 'info', // 'success', 'error', 'info'
    double duration = 2.0,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('show', {
        'message': message,
        'style': style,
        'duration': duration,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing toast: $e');
      return false;
    }
  }
}

/// Power button for SSH connection control
class LiquidGlassPowerButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_power_button');
  
  static Future<bool> isSupported() async => true;
  
  static Future<bool> show({required bool isConnected}) async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassPowerButton', {'isConnected': isConnected});
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
      final bool? result = await _channel.invokeMethod('updatePowerButtonState', {'isConnected': isConnected});
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating power button state: $e');
      return false;
    }
  }
  
  static Future<bool> showSuccessAnimation() async {
    try {
      final bool? result = await _channel.invokeMethod('showSuccessAnimation');
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing success animation: $e');
      return false;
    }
  }
  
  static Future<bool> showDisconnectAlert() async {
    try {
      final bool? result = await _channel.invokeMethod('showDisconnectAlert');
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing disconnect alert: $e');
      return false;
    }
  }
  
  // Store callbacks internally
  static VoidCallback? _onPowerButtonTapped;
  static VoidCallback? _onDisconnectConfirmed;
  static VoidCallback? _onDisconnectCancelled;
  
  static void setOnPowerButtonTappedCallback(VoidCallback callback) {
    _onPowerButtonTapped = callback;
    _updateMethodHandler();
  }
  
  static void setDisconnectCallbacks({
    required VoidCallback onConfirmed,
    required VoidCallback onCancelled,
  }) {
    _onDisconnectConfirmed = onConfirmed;
    _onDisconnectCancelled = onCancelled;
    _updateMethodHandler();
  }
  
  // Single method handler that handles all callbacks
  static void _updateMethodHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPowerButtonTapped':
          _onPowerButtonTapped?.call();
          break;
        case 'onDisconnectConfirmed':
          _onDisconnectConfirmed?.call();
          break;
        case 'onDisconnectCancelled':
          _onDisconnectCancelled?.call();
          break;
      }
    });
  }
}

/// Info button for navigation to info/help screen
class LiquidGlassInfoButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_info_button');
  
  static Future<bool> isSupported() async => true;
  
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
      if (call.method == 'onInfoButtonTapped') callback();
    });
  }
}

/// History button to quickly load recent SSH credentials
class LiquidGlassHistoryButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_history_button');
  static Function()? _onHistoryTapped;
  
  static Future<bool> isSupported() async => true;
  
  static Future<bool> show() async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassHistoryButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error showing liquid glass history button: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool? result = await _channel.invokeMethod('disableNativeLiquidGlassHistoryButton');
      return result ?? false;
    } catch (e) {
      debugPrint('Error hiding liquid glass history button: $e');
      return false;
    }
  }
  
  static void setOnHistoryTappedCallback(Function() onHistoryTapped) {
    _onHistoryTapped = onHistoryTapped;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHistoryTapped') {
        debugPrint('🕐 History button tapped callback');
        _onHistoryTapped?.call();
      }
    });
  }
}

// SshService - Simplified for better shell session management
class SshService extends ChangeNotifier {
  dartssh2.SSHClient? _client;
  Timer? _keepAliveTimer;
  Timer? _connectionCheckTimer;
  
  // Connection state tracking and credentials for reconnection
  String? _lastHost;
  int? _lastPort;
  String? _lastUsername;
  String? _lastPassword;
  String? _lastPrivateKey;
  String? _lastPrivateKeyPassphrase;
  bool _reconnecting = false;

  // Connection state tracking
  bool get isConnected {
    final clientExists = _client != null;
    final notClosed = clientExists && !_client!.isClosed;
    debugPrint('SSH connection status: exists=$clientExists, notClosed=$notClosed');
    return clientExists && notClosed;
  }
  
  // Get the connected host IP
  String? get hostIp => _lastHost;

  // Connect to SSH server
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    try {
      // Save credentials for potential reconnection
      _lastHost = host;
      _lastPort = port;
      _lastUsername = username;
      _lastPassword = password;
      _lastPrivateKey = privateKey;
      _lastPrivateKeyPassphrase = privateKeyPassphrase;
      
      debugPrint('SSH connect attempt: $username@$host:$port');
      
      // Create socket
      final socket = await dartssh2.SSHSocket.connect(host, port);
      debugPrint('SSH socket connected');
      
      // Prepare authentication options
      List<dartssh2.SSHKeyPair>? identities;
      
      // Handle private key if provided
      if (privateKey != null && privateKey.isNotEmpty) {
        try {
          debugPrint('Attempting to parse private key');
          debugPrint('Private key length: ${privateKey.length}');
          debugPrint('Has passphrase: ${privateKeyPassphrase != null && privateKeyPassphrase.isNotEmpty}');
          
          // Clean up the key
          var key = privateKey.trim();
          
          // Check if key already has proper format
          if (!key.contains('-----BEGIN')) {
            debugPrint('Adding OpenSSH headers to private key');
            key = '-----BEGIN OPENSSH PRIVATE KEY-----\n$key\n-----END OPENSSH PRIVATE KEY-----';
          } else {
            debugPrint('Private key already has headers');
          }
          
          // Parse the key with passphrase if provided
          identities = dartssh2.SSHKeyPair.fromPem(key, privateKeyPassphrase);
          debugPrint('Private key parsed successfully');
          debugPrint('Number of identities: ${identities.length}');
        } catch (e) {
          debugPrint('Error parsing private key with OpenSSH format: $e');
          
          // If OpenSSH format fails, try with RSA format
          try {
            debugPrint('Trying RSA format instead');
            var key = privateKey.trim();
            key = key.replaceAll('OPENSSH PRIVATE KEY', 'RSA PRIVATE KEY');
            identities = dartssh2.SSHKeyPair.fromPem(key, privateKeyPassphrase);
            debugPrint('Private key parsed successfully with RSA format');
            debugPrint('Number of identities: ${identities.length}');
          } catch (e2) {
            debugPrint('Error parsing private key with RSA format: $e2');
            throw Exception('Failed to parse private key. Please check the key format.');
          }
        }
      }
      
      // Create SSH client
      debugPrint('Creating SSH client with username: $username');
      debugPrint('Has password: ${password != null && password.isNotEmpty}');
      debugPrint('Has identities: ${identities != null && identities.isNotEmpty}');
      
      _client = dartssh2.SSHClient(
        socket,
        username: username,
        onPasswordRequest: () {
          debugPrint('Password requested by server (this could mean key auth failed and server is falling back to password)');
          // If we have a private key but server is asking for password, 
          // it likely means the key isn't authorized on the server
          if (identities != null && identities.isNotEmpty) {
            debugPrint('We provided a private key but server still wants password - key likely not authorized');
          }
          final response = password ?? '';
          debugPrint('Responding with password: ${response.isNotEmpty ? '[PROVIDED]' : '[EMPTY]'}');
          return response;
        },
        identities: identities,
      );
      
      // Wait for authentication to complete
      debugPrint('Waiting for authentication...');
      await _client!.authenticated;
      debugPrint('SSH authentication successful');
      
      // Start maintenance
      _startKeepAlive();
      _startConnectionCheck();
      
      debugPrint('SSH connection established to $host:$port as $username');
      notifyListeners();
    } catch (e) {
      debugPrint('SSH Connection Error: $e');
      _client?.close();
      _client = null;
      rethrow;
    }
  }

  // Parse terminal output for server startup messages
  static int? parseServerPortFromOutput(String output) {
    // Common patterns for server startup messages
    final patterns = [
      RegExp(r'(?:localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{4,5})', caseSensitive: false),
      RegExp(r'port\s+(\d{4,5})', caseSensitive: false),
      RegExp(r'running\s+(?:on|at)\s+(?:port\s+)?(\d{4,5})', caseSensitive: false),
      RegExp(r'listening\s+on\s+(?:port\s+)?(\d{4,5})', caseSensitive: false),
      RegExp(r'server\s+started.*?(\d{4,5})', caseSensitive: false),
      RegExp(r'http://[^:]+:(\d{4,5})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(output);
      if (match != null && match.groupCount >= 1) {
        final portStr = match.group(1);
        if (portStr != null) {
          final port = int.tryParse(portStr);
          if (port != null && port >= 1000 && port <= 65535) {
            debugPrint('🎯 Detected server port from output: $port');
            return port;
          }
        }
      }
    }
    
    return null;
  }

  // Check if a specific port is open
  Future<bool> checkSpecificPort(int port) async {
    if (!isConnected) return false;
    
    try {
      // Try lsof first (most reliable)
      var result = await runCommandLenient('lsof -i :$port -sTCP:LISTEN 2>/dev/null | grep LISTEN');
      if (result != null && result.isNotEmpty && result.contains('LISTEN')) {
        return true;
      }
      
      // Try connection test
      result = await runCommandLenient('timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>&1 && echo "OPEN" || echo "CLOSED"');
      return result != null && result.contains('OPEN');
    } catch (e) {
      return false;
    }
  }

  // Detect running development server on common ports
  Future<int?> detectRunningServer() async {
    if (!isConnected) {
      debugPrint('Cannot detect server: not connected');
      return null;
    }

    // Common development server ports to check (prioritized order)
    // Removed 5000 - not commonly used for web development
    final List<int> commonPorts = [3000, 8080, 5173, 4200, 8000, 3001, 5174];
    
    debugPrint('🔍 Checking for running servers on common ports...');
    
    for (final port in commonPorts) {
      try {
        // Try multiple detection methods for maximum compatibility
        // Method 1: lsof (most reliable if available)
        var result = await runCommandLenient('lsof -i :$port -sTCP:LISTEN 2>/dev/null | grep LISTEN');
        
        if (result != null && result.isNotEmpty && result.contains('LISTEN')) {
          debugPrint('✅ Found server on port $port (via lsof)');
          return port;
        }
        
        // Method 2: ss command
        result = await runCommandLenient('ss -tuln 2>/dev/null | grep ":$port "');
        
        if (result != null && result.isNotEmpty && result.contains(':$port')) {
          debugPrint('✅ Found server on port $port (via ss)');
          return port;
        }
        
        // Method 3: netstat
        result = await runCommandLenient('netstat -tuln 2>/dev/null | grep ":$port "');
        
        if (result != null && result.isNotEmpty && result.contains(':$port')) {
          debugPrint('✅ Found server on port $port (via netstat)');
          return port;
        }
        
        // Method 4: Check if we can connect to the port
        result = await runCommandLenient('timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>&1 && echo "OPEN" || echo "CLOSED"');
        
        if (result != null && result.contains('OPEN')) {
          debugPrint('✅ Found server on port $port (via connection test)');
          return port;
        }
        
      } catch (e) {
        debugPrint('Error checking port $port: $e');
      }
    }
    
    debugPrint('❌ No development server detected on common ports');
    return null;
  }

  // Disconnect from SSH server
  Future<void> disconnect() async {
    debugPrint('Disconnecting SSH session');
    
    try {
      // Kill all tmux sessions before disconnecting
      if (_client != null && isConnected) {
        debugPrint('🧹 Cleaning up all tmux sessions...');
        try {
          final session = await _client!.execute('tmux kill-server 2>/dev/null || true');
          await session.done;
          debugPrint('✅ All tmux sessions killed');
        } catch (e) {
          debugPrint('⚠️ Error killing tmux sessions (may not exist): $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error during tmux cleanup: $e');
    }
    
    _stopKeepAlive();
    _stopConnectionCheck();
    _client?.close();
    _client = null;
    // Clear saved credentials
    _lastHost = null;
    _lastPort = null;
    _lastUsername = null;
    _lastPassword = null;
    _lastPrivateKey = null;
    _lastPrivateKeyPassphrase = null;
    debugPrint('SSH connection closed');
    
    // Ensure listeners are notified of disconnection
    notifyListeners();
    
    // Small delay to ensure state propagation
    await Future.delayed(const Duration(milliseconds: 100));
  }
  
  // Keep the connection alive using lightweight SSH-level keepalive
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (isConnected) {
        try {
          debugPrint('Sending keep-alive ping (SSH-level)');
          // Use SSH protocol-level keep-alive instead of creating a new channel
          // This sends a null packet that doesn't consume channels
          if (_client != null && !_client!.isClosed) {
            // The connection is alive, no need to test with echo
            // The SSH library handles protocol-level keepalive automatically
            debugPrint('Connection alive via SSH protocol keepalive');
          }
        } catch (e) {
          debugPrint('Keep-alive check failed: $e');
          _tryReconnect();
        }
      }
    });
  }
  
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }
  
  // Periodically check connection status
  void _startConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_client != null && _client!.isClosed) {
        debugPrint('Connection check: SSH client is closed, attempting reconnect');
        _tryReconnect();
      }
    });
  }
  
  void _stopConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
  }
  
  // Try to reconnect using saved credentials
  Future<void> _tryReconnect() async {
    if (_reconnecting || _lastHost == null || _lastUsername == null) {
      return;
    }
    
    _reconnecting = true;
    debugPrint('Attempting to reconnect to $_lastHost');
    
    try {
      // Close existing client if any
      _client?.close();
      _client = null;
      
      // Reconnect with saved credentials
      await connect(
        host: _lastHost!,
        port: _lastPort!,
        username: _lastUsername!,
        password: _lastPassword,
        privateKey: _lastPrivateKey,
        privateKeyPassphrase: _lastPrivateKeyPassphrase,
      );
      
      debugPrint('Reconnection successful');
    } catch (e) {
      debugPrint('Reconnection failed: $e');
    } finally {
      _reconnecting = false;
    }
  }

  Future<dartssh2.SSHSession?> shell({int? terminalWidth, int? terminalHeight}) async {
    if (!isConnected) {
      debugPrint('DEBUG: SshService.shell() - Not connected.');
      return null;
    }
    try {
      // Use provided dimensions or defaults (50% screen height terminal window)
      final width = terminalWidth ?? 40;  // Conservative 40 chars for iPhone
      final height = terminalHeight ?? 50; // 50 rows for full screen
      
      debugPrint('DEBUG: SshService.shell() - Attempting to open shell with PTY and xterm-256color ($width x $height).');
      // Request a proper PTY with xterm-256color terminal type for full permissions and compatibility
      final session = await _client!.shell(
        pty: dartssh2.SSHPtyConfig(
          type: 'xterm-256color',
          width: width,
          height: height,
        ),
      );
      debugPrint('DEBUG: SshService.shell() - Shell with PTY (xterm-256color) opened successfully.');
      return session;
    } catch (e) {
      debugPrint('DEBUG: SshService.shell() - Error opening shell: $e');
      return null;
    }
  }

  // Run a command and get output
  Future<String?> runCommand(String command) async {
    if (!isConnected) {
      throw Exception('Not connected to SSH server');
    }
    
    debugPrint('Executing command: $command');
    
    final session = await _client!.execute(command);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutSubscription = session.stdout.listen((data) {
      stdoutBuffer.write(utf8.decode(data));
    });

    final stderrSubscription = session.stderr.listen((data) {
      stderrBuffer.write(utf8.decode(data));
    });

    // Wait for session to complete
    await session.done;
    
    // Cancel subscriptions
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();

    final output = stdoutBuffer.toString();
    final errorOutput = stderrBuffer.toString();
    
    debugPrint('Command exit code: ${session.exitCode}');

    if (session.exitCode != 0) {
      throw Exception('Command failed with exit code ${session.exitCode}:\n$errorOutput');
    }
    return output;
  }

  // Run command without throwing on non-zero exit codes with retry logic
  Future<String?> runCommandLenient(String command, {int maxRetries = 3}) async {
    if (!isConnected) {
      throw Exception('Not connected to SSH server');
    }
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('Executing command (attempt $attempt/$maxRetries): $command');
        
        final session = await _client!.execute(command);
        final stdoutBuffer = StringBuffer();
        final stderrBuffer = StringBuffer();

        final stdoutSubscription = session.stdout.listen((data) {
          stdoutBuffer.write(utf8.decode(data));
        });

        final stderrSubscription = session.stderr.listen((data) {
          stderrBuffer.write(utf8.decode(data));
        });

        // Wait for session to complete
        await session.done;
        
        // Cancel subscriptions
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();

        final output = stdoutBuffer.toString();
        final errorOutput = stderrBuffer.toString();
        
        // If there's stderr output, log it but don't fail
        if (errorOutput.isNotEmpty) {
          debugPrint('Command stderr: $errorOutput');
        }
        
        // Success - return stdout regardless of exit code
        debugPrint('Command completed successfully on attempt $attempt');
        return output;
        
      } catch (e) {
        debugPrint('Command failed on attempt $attempt: $e');
        
        // Check if it's a channel open error
        if (e.toString().contains('SSHChannelOpenError') || e.toString().contains('open failed')) {
          debugPrint('Channel open error detected, will retry...');
          
          // Wait before retry, with exponential backoff
          if (attempt < maxRetries) {
            final delay = Duration(milliseconds: 500 * attempt);
            debugPrint('Waiting ${delay.inMilliseconds}ms before retry...');
            await Future.delayed(delay);
            
            // Try to reconnect if needed
            if (!isConnected) {
              debugPrint('Connection lost, attempting to reconnect...');
              try {
                await _tryReconnect();
                if (!isConnected) {
                  throw Exception('Failed to reconnect SSH session');
                }
              } catch (reconnectError) {
                debugPrint('Reconnection failed: $reconnectError');
                if (attempt == maxRetries) {
                  throw Exception('SSH connection failed after $maxRetries attempts: $e');
                }
              }
            }
            continue; // Retry
          }
        }
        
        // If it's the last attempt or not a channel error, throw
        if (attempt == maxRetries) {
          throw Exception('Command failed after $maxRetries attempts: $e');
        }
        
        // Wait before retry for other errors
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
    
    // Should never reach here
    throw Exception('Unexpected error in runCommandLenient');
  }

  // SFTP operations
  Future<dartssh2.SftpClient> sftp() async {
    if (!isConnected) {
      throw Exception('Not connected to SSH server');
    }
    return await _client!.sftp();
  }

  // DEPRECATED: Legacy file tree editor methods (removed - no longer needed)
  // File management simplified to terminal-only workflow
  
  /* REMOVED - Old SFTP file browser code
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    if (!isConnected) {
      throw Exception('Not connected to SSH server');
    }
    final sftpClient = await _client!.sftp();
    final List<FileSystemEntity> entities = [];

    try {
      await for (var nameList in sftpClient.readdir(path)) {
        for (var item in nameList) {
          final name = item.filename;
          if (name == '.' || name == '..') {
            continue;
          }
          final isDirectory = item.longname.startsWith('d');
          final type = isDirectory ? FileSystemEntityType.directory : FileSystemEntityType.file;
          final entityPath = '$path/$name';
          entities.add(FileSystemEntity(name: name, path: entityPath, type: type));
        }
      }
    } on dartssh2.SftpStatusError catch (e) {
      if (e.code == 2) { // SFTP_NO_SUCH_FILE
        debugPrint('Directory not found: $path');
        return [];
      } else {
        rethrow;
      }
    }
    return entities;
  }

  Future<List<FileSystemEntity>> listDirectoryWithRetry(
    String path, {
    int maxRetries = 6,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    debugPrint('📁 Loading directory: $path');
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Check connection before each attempt
        if (!isConnected) {
          debugPrint('🔄 Reconnecting SSH (attempt ${attempt + 1})');
          await _tryReconnect();
          await Future.delayed(const Duration(milliseconds: 200));
        }
        
        final result = await listDirectory(path);
        debugPrint('✅ Directory listing successful: ${result.length} items found');
        if (result.isNotEmpty) {
          debugPrint('✅ Sample files: ${result.take(3).map((e) => e.name).join(', ')}${result.length > 3 ? '...' : ''}');
        }
        return result; // Return immediately on success, even if empty
        
      } on dartssh2.SftpStatusError catch (e) {
        if (e.code == 2) {
          // SFTP_NO_SUCH_FILE - directory doesn't exist
          debugPrint('❌ SFTP: Directory not found: $path (code 2)');
          throw Exception('Directory does not exist: $path');
        } else {
          debugPrint('❌ SFTP error (code ${e.code}): ${e.message} (attempt ${attempt + 1})');
          if (attempt == maxRetries - 1) rethrow;
          await Future.delayed(delay);
        }
      } on dartssh2.SSHChannelOpenError catch (e) {
        debugPrint('❌ SSH channel error: $e (attempt ${attempt + 1})');
        if (attempt == maxRetries - 1) rethrow;
        await _tryReconnect();
        await Future.delayed(delay);
      } catch (e) {
        debugPrint('❌ Directory listing error: $e (attempt ${attempt + 1})');
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(delay);
      }
    }
    
    // This should never be reached due to rethrow above, but just in case
    throw Exception('Failed to list directory after $maxRetries attempts');
  }
  */

  Future<String?> readFile(String path) async {
    if (!isConnected) {
      throw Exception('Not connected to SSH server');
    }
    return await runCommand('cat "$path"');
  }
}

// Update the SshServiceNotifier class
class SshServiceNotifier extends StateNotifier<SshService> {
  final SshService _sshService = SshService();

  SshServiceNotifier() : super(SshService());

  @override
  SshService get state => _sshService;

  @override
  set state(SshService value) {
    // This setter is intentionally left empty because _sshService is final.
    // The actual state changes are managed by notifyListeners() within SshService.
  }

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    await _sshService.connect(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey,
      privateKeyPassphrase: privateKeyPassphrase,
    );
  }

  Future<void> disconnect() async {
    await _sshService.disconnect();
  }
  
  // Detect running development server
  Future<int?> detectRunningServer() async {
    return await _sshService.detectRunningServer();
  }
  
  // Check connection status and reconnect if needed
  Future<bool> ensureConnected() async {
    debugPrint('Ensuring SSH connection is active');
    if (!_sshService.isConnected) {
      debugPrint('SSH connection lost, attempting to reconnect');
      try {
        // This will use the saved credentials from the service
        await _sshService._tryReconnect();
        return _sshService.isConnected;
      } catch (e) {
        debugPrint('Failed to reconnect: $e');
        return false;
      }
    }
    return true;
  }
  
  @override
  void dispose() {
    debugPrint('SshServiceNotifier being disposed - NOT disconnecting');
    // Do NOT disconnect here - we want the connection to persist
    super.dispose();
  }
}

// Provider for SshServiceNotifier - make it persist
final sshServiceProvider = StateNotifierProvider<SshServiceNotifier, SshService>((ref) {
  final notifier = SshServiceNotifier();
  ref.onDispose(() {
    debugPrint('sshServiceProvider being disposed - NOT disconnecting');
    // Do NOT disconnect here - we want the connection to persist
  });
  return notifier;
});

// CredentialStorageService
class CredentialStorageService {
  static const _ipKey = 'server_ip';
  static const _portKey = 'server_port';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';
  static const _privateKey = 'private_key';
  static const _privateKeyPassphrase = 'private_key_passphrase';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<void> saveCredentials({
    required String ip,
    required int port,
    required String username,
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipKey, ip);
    await prefs.setInt(_portKey, port);
    await prefs.setString(_usernameKey, username);
    if (password != null) {
      await _secureStorage.write(key: _passwordKey, value: password);
    } else {
      await _secureStorage.delete(key: _passwordKey);
    }
    if (privateKey != null) {
      await _secureStorage.write(key: _privateKey, value: privateKey);
    } else {
      await _secureStorage.delete(key: _privateKey);
    }
    if (privateKeyPassphrase != null) {
      await _secureStorage.write(key: _privateKeyPassphrase, value: privateKeyPassphrase);
    } else {
      await _secureStorage.delete(key: _privateKeyPassphrase);
    }
  }

  Future<Map<String, dynamic>?> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_ipKey);
    final port = prefs.getInt(_portKey);
    final username = prefs.getString(_usernameKey);
    final password = await _secureStorage.read(key: _passwordKey);
    final privateKey = await _secureStorage.read(key: _privateKey);
    final privateKeyPassphrase = await _secureStorage.read(key: _privateKeyPassphrase);

    if (ip != null && port != null && username != null) {
      return {
        'ip': ip,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'privateKeyPassphrase': privateKeyPassphrase,
      };
    }
    return null;
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ipKey);
    await prefs.remove(_portKey);
    await prefs.remove(_usernameKey);
    await _secureStorage.delete(key: _passwordKey);
    await _secureStorage.delete(key: _privateKey);
    await _secureStorage.delete(key: _privateKeyPassphrase);
  }
}

// CredentialStorageService


// Providers
final credentialStorageServiceProvider = Provider<CredentialStorageService>((ref) {
  return CredentialStorageService();
});

final sshIsLoadingProvider = StateProvider<bool>((ref) => false);
final sshPasswordVisibleProvider = StateProvider<bool>((ref) => false);

final connectedIpProvider = StateProvider<String?>((ref) => null);
final connectedUsernameProvider = StateProvider<String?>((ref) => null);

// Provider to track detected server port from terminal output
final detectedServerPortProvider = StateProvider<int?>((ref) => null);

// Provider to cache the last preview URL for instant toggle
final cachedPreviewUrlProvider = StateProvider<String?>((ref) => null);

final credentialsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final creds = await ref.read(credentialStorageServiceProvider).loadCredentials();
  if (creds != null) {
    ref.read(connectedIpProvider.notifier).state = creds['ip'];
    ref.read(connectedUsernameProvider.notifier).state = creds['username'];
  }
  return creds;
});

// SSHSession Widget
class SSHSession extends ConsumerStatefulWidget {
  const SSHSession({super.key});

  @override
  ConsumerState<SSHSession> createState() => _SSHSessionState();
}

class _SSHSessionState extends ConsumerState<SSHSession> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _privateKeyPassphraseController;
  bool? _liquidGlassSupported; // null until checked
  late AnimationController _rotationController;
  bool _isLoadingCredentials = false;

  @override
  void initState() {
    super.initState();
    final credentials = ref.read(credentialsProvider).value;
    _ipController = TextEditingController(text: credentials?['ip'] ?? '');
    _portController = TextEditingController(text: credentials?['port']?.toString() ?? '22');
    _usernameController = TextEditingController(text: credentials?['username'] ?? '');
    _passwordController = TextEditingController(text: credentials?['password'] ?? '');
    _privateKeyController = TextEditingController(text: credentials?['privateKey'] ?? '');
    _privateKeyPassphraseController = TextEditingController(text: '');
    
    // Initialize rotation animation controller
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // Initialize liquid glass buttons
    _initLiquidGlassButtons();
  }
  
  void _registerPowerButtonCallback() {
    // Always ensure the SSH screen's callback is active
    LiquidGlassPowerButton.setOnPowerButtonTappedCallback(() {
      _handlePowerButtonTap();
    });
  }
  
  Future<void> _initLiquidGlassButtons() async {
    final supported = await LiquidGlassPowerButton.isSupported();
    setState(() {
      _liquidGlassSupported = supported;
    });
    
    if (supported) {
      // Initialize power button
      await _initLiquidGlassPowerButton();
      
      // Initialize info button
      await _initLiquidGlassInfoButton();
      
      // Initialize history button
      await _initLiquidGlassHistoryButton();
    }
  }
  
  Future<void> _initLiquidGlassPowerButton() async {
    // Set up callback for power button taps
    _registerPowerButtonCallback();
    
    // Show the power button with initial connection state
    final currentSshService = ref.read(sshServiceProvider);
    await LiquidGlassPowerButton.show(
      isConnected: currentSshService.isConnected,
    );
  }
  
  Future<void> _initLiquidGlassInfoButton() async {
    // Info button handles sheet natively in Swift - no callback needed
    // Just show the button
    await LiquidGlassInfoButton.show();
  }
  
  Future<void> _initLiquidGlassHistoryButton() async {
    // History button is now embedded in the IP field as a clock icon
    // Don't show the floating native button anymore
    debugPrint('✅ History button embedded in IP field');
  }
  
  Future<void> _loadRecentCredentials() async {
    if (_isLoadingCredentials) return; // Prevent multiple taps
    
    setState(() {
      _isLoadingCredentials = true;
    });
    
    // Start rotation animation
    _rotationController.repeat();
    
    debugPrint('🔄 Loading recent credentials');
    
    // Load saved credentials
    final credentials = await ref.read(credentialStorageServiceProvider).loadCredentials();
    
    // Stop rotation animation
    await _rotationController.forward(from: 0);
    _rotationController.stop();
    
    if (credentials != null && mounted) {
      setState(() {
        _ipController.text = credentials['ip'] ?? '';
        _portController.text = credentials['port']?.toString() ?? '22';
        _usernameController.text = credentials['username'] ?? '';
        _passwordController.text = credentials['password'] ?? '';
        _privateKeyController.text = credentials['privateKey'] ?? '';
        _privateKeyPassphraseController.text = '';
        _isLoadingCredentials = false;
      });
      
      // Show native iOS toast
      await LiquidGlassToast.show(
        message: 'Recent credentials loaded',
        style: 'success',
        duration: 1.5,
      );
    } else if (mounted) {
      setState(() {
        _isLoadingCredentials = false;
      });
      
      // No saved credentials - show native iOS toast
      await LiquidGlassToast.show(
        message: 'No recent credentials found',
        style: 'info',
        duration: 1.5,
      );
    }
  }
  
  void _handlePowerButtonTap() async {
    final currentSshService = ref.read(sshServiceProvider);
    if (currentSshService.isConnected) {
      // Navigate to Terminal screen (disable swipe-back to preserve power button flow)
      if (mounted) {
        await Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const TerminalScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                )),
                child: child,
              );
            },
          ),
        );
        
          // When returning from Terminal, restore SSH screen UI
          if (mounted) {
            // Re-register power button callback for SSH screen
            _registerPowerButtonCallback();
            
            // Ensure play button is hidden (should be from Terminal cleanup, but double-check)
            await LiquidGlassPlayButton.hide();
            
            debugPrint('✅ Returned to SSH screen, UI restored');
          }
      }
    } else {
      // Not connected - attempt to connect
      _connect();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _privateKeyPassphraseController.dispose();
    _rotationController.dispose();
    
    // Keep Power and Info buttons visible - they persist across SSH/Terminal screens
    // The Terminal screen will manage their state when navigating
    
    // Do NOT disconnect here. Only dispose controllers.
    super.dispose();
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      ref.read(sshIsLoadingProvider.notifier).state = true;
      try {
        // Add timeout to prevent infinite loading
        await Future.any([
          ref.read(sshServiceProvider.notifier).connect(
                host: _ipController.text,
                port: int.parse(_portController.text),
                username: _usernameController.text,
                password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
                privateKey: _privateKeyController.text.isNotEmpty ? _privateKeyController.text : null,
                privateKeyPassphrase: _privateKeyPassphraseController.text.isNotEmpty ? _privateKeyPassphraseController.text : null,
              ),
          Future.delayed(const Duration(seconds: 30)).then((_) => throw Exception('Connection timeout after 30 seconds')),
        ]);

        await ref.read(credentialStorageServiceProvider).saveCredentials(
              ip: _ipController.text,
              port: int.parse(_portController.text),
              username: _usernameController.text,
              password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
              privateKey: _privateKeyController.text.isNotEmpty ? _privateKeyController.text : null,
              privateKeyPassphrase: _privateKeyPassphraseController.text.isNotEmpty ? _privateKeyPassphraseController.text : null,
            );

        ref.read(connectedIpProvider.notifier).state = _ipController.text;
        ref.read(connectedUsernameProvider.notifier).state = _usernameController.text;
        
        // Show checkmark animation then update to connected state
        await LiquidGlassPowerButton.showSuccessAnimation();
        await Future.delayed(const Duration(milliseconds: 800));
        await LiquidGlassPowerButton.updateState(isConnected: true);
        
        // Auto-navigate to Terminal screen after successful connection (disable swipe-back)
        if (mounted) {
          await Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const TerminalScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  )),
                  child: child,
                );
              },
            ),
          );
          
          // When returning from Terminal, restore SSH screen UI
          if (mounted) {
            // Re-register power button callback for SSH screen
            _registerPowerButtonCallback();
            
            // Ensure play button is hidden (should be from Terminal cleanup, but double-check)
            await LiquidGlassPlayButton.hide();
            
            debugPrint('✅ Returned to SSH screen, UI restored');
          }
        }
      } catch (e) {
        // Provide more specific error messages
        String errorMessage = 'Failed to connect';
        String errorDetails = e.toString().toLowerCase();
        
        if (errorDetails.contains('timeout') || errorDetails.contains('connection timeout')) {
          errorMessage = 'Connection timeout - check server IP and port';
        } else if (errorDetails.contains('connection refused') || errorDetails.contains('unreachable')) {
          errorMessage = 'Server unreachable - check IP address and port';
        } else if (errorDetails.contains('authentication') || errorDetails.contains('auth') || errorDetails.contains('password') || errorDetails.contains('permission denied')) {
          errorMessage = 'Authentication failed - check username and password/key';
        } else if (errorDetails.contains('private key') || errorDetails.contains('key')) {
          errorMessage = 'Private key error - check key format and passphrase';
        } else if (errorDetails.contains('host key') || errorDetails.contains('fingerprint')) {
          errorMessage = 'Host key verification failed';
        } else if (errorDetails.contains('socket') || errorDetails.contains('network')) {
          errorMessage = 'Network error - check your internet connection';
        } else {
          errorMessage = 'Connection failed: ${e.toString()}';
        }

        // Show native iOS error alert
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Connection Failed'),
            content: Text(errorMessage),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      } finally {
        ref.read(sshIsLoadingProvider.notifier).state = false;
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isPasswordVisible = ref.watch(sshPasswordVisibleProvider);
    
    // Re-register callback whenever build is called (e.g., when returning from Terminal)
    // This ensures SSH screen's callback is active
    if (_liquidGlassSupported == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _registerPowerButtonCallback();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      resizeToAvoidBottomInset: false, // Prevent resize when keyboard appears
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0a),
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24.0,
              MediaQuery.of(context).padding.top, // Safe area top
              24.0,
              24.0 + MediaQuery.of(context).viewInsets.bottom, // Add keyboard height to bottom padding
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    // Title
                    Text(
                      'Create the future.',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.8,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 3),
                            blurRadius: 6,
                            color: Colors.black.withAlpha((255 * 0.7).round()),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    
                    // Server IP and Port Fields
                    Row(
                      children: [
                        Expanded(
                          flex: 7, // Increased from 6 to make IP field longer
                          child: TextFormField(
                            controller: _ipController,
                              decoration: InputDecoration(
                              labelText: 'Server IP',
                              labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                              suffixIcon: IconButton(
                                icon: RotationTransition(
                                  turns: _rotationController,
                                  child: const Icon(
                                    CupertinoIcons.refresh,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                onPressed: _loadRecentCredentials,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                              ),
                              filled: true,
                              fillColor: Colors.black,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            ),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3, // Decreased from 4 to make port field smaller
                          child: TextFormField(
                            controller: _portController,
                            decoration: InputDecoration(
                              labelText: 'Port',
                              labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                              ),
                              filled: true,
                              fillColor: Colors.black,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            ),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Username Field (Full Width)
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                      validator: (value) => value!.isEmpty ? 'Required' : null,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Password Field (Full Width)
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        suffixIcon: IconButton(
                          icon: Icon(
                            CupertinoIcons.eye,
                            size: 20,
                            color: isPasswordVisible ? Colors.white : Colors.white70,
                          ),
                          onPressed: () {
                            ref.read(sshPasswordVisibleProvider.notifier).state = !isPasswordVisible;
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                      obscureText: !isPasswordVisible,
                      validator: (value) {
                        if (value!.isEmpty && _privateKeyController.text.isEmpty) {
                          return 'Password or private key required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),
                    
                    // Private Key Field
                    TextFormField(
                      controller: _privateKeyController,
                      decoration: InputDecoration(
                        labelText: 'Private Key (optional)',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),
                    // Private Key Passphrase Field
                    TextFormField(
                      controller: _privateKeyPassphraseController,
                      decoration: InputDecoration(
                        labelText: 'Private Key Passphrase (optional)',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.3).round())),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.6).round())),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      ),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                      obscureText: !isPasswordVisible,
                      textInputAction: TextInputAction.done,
                    ),
                    
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Add back the HomeScreen class that was accidentally removed
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// Simplified _HomeScreenState - no more bottom navigation
class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _checkingConnection = false;

  @override
  void initState() {
    super.initState();
    // Schedule connection check after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    if (_checkingConnection) return;
    _checkingConnection = true;
    
    try {
      final sshNotifier = ref.read(sshServiceProvider.notifier);
      await sshNotifier.ensureConnected();
    } catch (e) {
      debugPrint('Error checking connection: $e');
    } finally {
      _checkingConnection = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      extendBody: true,
      body: Center(
        child: SSHSession(),
      ),
    );
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: Colors.black,
      child: child,
    );
  }
}
