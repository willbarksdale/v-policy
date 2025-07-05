import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'edit.dart';


// SshService
class SshService {
  SSHClient? _client;

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
  }) async {
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        onPasswordRequest: () => password, // Use the password via callback
        // Only use identities if privateKey is provided and password is not
        identities: (privateKey != null && password == null) ? [SSHKeyPair.fromPem(privateKey) as SSHKeyPair] : null,
      );
    } catch (e) {
      debugPrint('SSH Connection Error: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
  }

  Future<String?> runCommand(String command) async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    
    debugPrint('Executing command: $command'); // Debug
    
    final session = await _client!.execute(command);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    // Use StreamSubscription to properly handle the streams
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
    
    debugPrint('Regular command exit code: ${session.exitCode}'); // Debug
    debugPrint('Regular command stdout length: ${output.length}'); // Debug
    debugPrint('Regular command stderr length: ${errorOutput.length}'); // Debug

    if (session.exitCode != 0) {
      throw Exception('Command failed with exit code ${session.exitCode}:\n$errorOutput');
    }
    return output;
  }

  Future<SSHSession> runCommandInBackground(String command) async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    // Execute the command in the background using nohup
    final session = await _client!.execute('nohup $command > /dev/null 2>&1 &');
    return session;
  }

  Future<SSHSession> startShell() async {

    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    return await _client!.shell();
  }

  Future<SftpClient> sftp() async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    return await _client!.sftp();
  }

  bool get isConnected => _client != null && _client!.isClosed == false;

  Future<List<FileSystemEntity>> listDirectory(String path) async {
    if (_client == null) {
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
    } on SftpStatusError catch (e) {
      if (e.code == 2) { // SFTP_NO_SUCH_FILE
        debugPrint('Directory not found: $path');
        return [];
      } else {
        rethrow;
      }
    }
    return entities;
  }

  Future<String?> readFile(String path) async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    return await runCommand('cat "$path"');
  }

  // Run command without throwing on non-zero exit codes (useful for find, ls, etc.)
  Future<String?> runCommandLenient(String command) async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    
    debugPrint('Executing lenient command: $command'); // Debug
    
    final session = await _client!.execute(command);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    // Use StreamSubscription to properly handle the streams
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
    
    debugPrint('Lenient command exit code: ${session.exitCode}'); // Debug
    debugPrint('Lenient command stdout length: ${output.length}'); // Debug
    debugPrint('Lenient command stderr length: ${errorOutput.length}'); // Debug
    
    // If there's stderr output, log it but don't fail
    if (errorOutput.isNotEmpty) {
      debugPrint('Command stderr: $errorOutput');
    }
    
    // Return stdout regardless of exit code (empty string if no output)
    return output;
  }

  // Alternative simple command execution
  Future<String?> runCommandSimple(String command) async {
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    
    debugPrint('Executing simple command: $command'); // Debug
    
    try {
      final session = await _client!.execute(command);
      final stdoutBuffer = StringBuffer();

      // Use StreamSubscription to properly handle the streams
      final stdoutSubscription = session.stdout.listen((data) {
        stdoutBuffer.write(utf8.decode(data));
      });

      // Wait for session to complete
      await session.done;
      
      // Cancel subscription
      await stdoutSubscription.cancel();

      final result = stdoutBuffer.toString();
      debugPrint('Simple command result length: ${result.length}'); // Debug
      debugPrint('Simple command exit code: ${session.exitCode}'); // Debug
      return result;
    } catch (e) {
      debugPrint('Simple command failed: $e'); // Debug
      return null;
    }
  }
}

// New: StateNotifier for SshService
class SshServiceNotifier extends StateNotifier<SshService> {
  SshServiceNotifier() : super(SshService()); // Initial state is a new SshService

  // Expose the connect method from the current SshService instance
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
  }) async {
    await state.connect(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey,
    );
    // Force Riverpod to notify listeners that the state has changed
    state = state;
  }

  Future<void> disconnect() async {
    await state.disconnect();
    // Optionally, reset state to a new, disconnected SshService instance
    state = SshService();
  }
}

// New: Provider for SshServiceNotifier
final sshServiceProvider = StateNotifierProvider<SshServiceNotifier, SshService>((ref) {
  return SshServiceNotifier();
});