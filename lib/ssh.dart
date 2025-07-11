import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';
import 'package:iconify_flutter/icons/material_symbols.dart';
import 'edit.dart';
import 'terminal.dart';
import 'preview.dart';
import 'info.dart';

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

  // Disconnect from SSH server
  Future<void> disconnect() async {
    debugPrint('Disconnecting SSH session');
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
  
  // Keep the connection alive
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (isConnected) {
        try {
          debugPrint('Sending keep-alive ping');
          await runCommandLenient('echo "ping"');
        } catch (e) {
          debugPrint('Keep-alive failed: $e');
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

  Future<dartssh2.SSHSession?> shell() async {
    if (!isConnected) {
      debugPrint('DEBUG: SshService.shell() - Not connected.');
      return null;
    }
    try {
      debugPrint('DEBUG: SshService.shell() - Attempting to open shell.');
      final session = await _client!.shell();
      debugPrint('DEBUG: SshService.shell() - Shell opened successfully.');
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

class _SSHSessionState extends ConsumerState<SSHSession> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _privateKeyPassphraseController;

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
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _privateKeyPassphraseController.dispose();
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected!', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(connectedIpProvider.notifier).state = _ipController.text;
        ref.read(connectedUsernameProvider.notifier).state = _usernameController.text;
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.withAlpha(200),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      } finally {
        ref.read(sshIsLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await ref.read(sshServiceProvider.notifier).disconnect();
      
      // Clear connection state immediately
      ref.read(connectedIpProvider.notifier).state = null;
      ref.read(connectedUsernameProvider.notifier).state = null;
      
      // Force UI refresh by triggering a rebuild
      if (mounted) {
        setState(() {});
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session ended', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to disconnect: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPasswordVisible = ref.watch(sshPasswordVisibleProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 24.0),
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
                        fontWeight: FontWeight.w400,
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
                          flex: 1,
                          child: TextFormField(
                            controller: _ipController,
                            decoration: InputDecoration(
                              labelText: 'Server IP',
                              labelStyle: const TextStyle(color: Colors.white70),
                              suffixIcon: Consumer(
                                builder: (context, ref, child) {
                                  final currentSshService = ref.watch(sshServiceProvider);
                                  final currentIsLoading = ref.watch(sshIsLoadingProvider);
                                  
                                  return currentIsLoading 
                                    ? const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                        ),
                                      )
                                    : IconButton(
                                        icon: Icon(
                                          Icons.power_settings_new, 
                                          size: 20, 
                                          color: currentSshService.isConnected ? Colors.green : Colors.white70,
                                        ),
                                        onPressed: () {
                                          if (currentSshService.isConnected) {
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
                                                    onPressed: () => Navigator.pop(context),
                                                    icon: const Icon(Icons.close, color: Colors.white),
                                                  ),
                                                  IconButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      _disconnect();
                                                    },
                                                    icon: const Icon(Icons.check, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                            );
                                          } else {
                                            _connect();
                                          }
                                        },
                                      );
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
                            ),
                            style: const TextStyle(color: Colors.white),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _portController,
                            decoration: InputDecoration(
                              labelText: 'Port',
                              labelStyle: const TextStyle(color: Colors.white70),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.info_outline, size: 20, color: Colors.white70),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const InfoScreenFullPage(),
                                    ),
                                  );
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
                            ),
                            style: const TextStyle(color: Colors.white),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Username and Password fields
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: const TextStyle(color: Colors.white70),
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
                            ),
                            style: const TextStyle(color: Colors.white),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.white70),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  size: 20,
                                  color: Colors.white70,
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
                            ),
                            style: const TextStyle(color: Colors.white),
                            obscureText: !isPasswordVisible,
                            validator: (value) {
                              if (value!.isEmpty && _privateKeyController.text.isEmpty) {
                                return 'Password or private key required';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    
                    // Private Key Field
                    TextFormField(
                      controller: _privateKeyController,
                      decoration: InputDecoration(
                        labelText: 'Private Key (optional)',
                        labelStyle: const TextStyle(color: Colors.white70),
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
                      ),
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),
                    // Private Key Passphrase Field
                    TextFormField(
                      controller: _privateKeyPassphraseController,
                      decoration: InputDecoration(
                        labelText: 'Private Key Passphrase (optional)',
                        labelStyle: const TextStyle(color: Colors.white70),
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
                      ),
                      style: const TextStyle(color: Colors.white),
                      obscureText: !isPasswordVisible,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
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

// Update the _HomeScreenState class
class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  bool _checkingConnection = false;

  static final List<Widget> _widgetOptions = <Widget>[
    const SSHSession(),
    const EditorScreen(),
    const TerminalScreen(),
    const PreviewScreen(),
  ];

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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    // Check connection when switching tabs
    _checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    // When returning to SSH tab (index 0), check connection
    if (_selectedIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkConnection();
      });
    }

    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Iconify(Mdi.chevron_up, color: Colors.white),
              label: 'SSH',
            ),
            BottomNavigationBarItem(
              icon: Iconify(MaterialSymbols.chevron_left, color: Colors.white,),
              label: 'Edit',
            ),
            BottomNavigationBarItem(
              icon: Iconify(MaterialSymbols.chevron_right, color: Colors.white,),
              label: 'Terminal',
            ),
            BottomNavigationBarItem(
              icon: Iconify(Mdi.chevron_down, color: Colors.white,),
              label: 'Preview',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          backgroundColor: Colors.black,
          elevation: 0,
        ),
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

class InfoScreenFullPage extends StatelessWidget {
  const InfoScreenFullPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const InfoScreen(),
    );
  }
}
