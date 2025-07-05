import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/mdi.dart';
import 'package:iconify_flutter/icons/material_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'edit.dart';
import 'terminal.dart';
import 'preview.dart';
import 'ssh.dart' as ssh;

// CredentialStorageService
class CredentialStorageService {
  static const _ipKey = 'server_ip';
  static const _portKey = 'server_port';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';
  static const _privateKey = 'private_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<void> saveCredentials({
    required String ip,
    required int port,
    required String username,
    String? password,
    String? privateKey,
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
  }

  Future<Map<String, dynamic>?> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_ipKey);
    final port = prefs.getInt(_portKey);
    final username = prefs.getString(_usernameKey);
    final password = await _secureStorage.read(key: _passwordKey);
    final privateKey = await _secureStorage.read(key: _privateKey);

    if (ip != null && port != null && username != null) {
      return {
        'ip': ip,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
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
  }
}

// Providers
final credentialStorageServiceProvider = Provider<CredentialStorageService>((ref) {
  return CredentialStorageService();
});

// LoginScreen
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await ref.read(credentialStorageServiceProvider).loadCredentials();
    if (credentials != null) {
      _ipController.text = credentials['ip'];
      _portController.text = credentials['port'].toString();
      _usernameController.text = credentials['username'];
      _passwordController.text = credentials['password'] ?? '';
      _privateKeyController.text = credentials['privateKey'] ?? '';
    }
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await ref.read(ssh.sshServiceProvider.notifier).connect(
              host: _ipController.text,
              port: int.parse(_portController.text),
              username: _usernameController.text,
              password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
              privateKey: _privateKeyController.text.isNotEmpty ? _privateKeyController.text : null,
            );

        await ref.read(credentialStorageServiceProvider).saveCredentials(
              ip: _ipController.text,
              port: int.parse(_portController.text),
              username: _usernameController.text,
              password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
              privateKey: _privateKeyController.text.isNotEmpty ? _privateKeyController.text : null,
            );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to connect: $e', style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.black,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
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
                      color: Colors.black.withValues(alpha: 0.7),
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
                    flex: 2,
                    child: TextFormField(
                      controller: _ipController,
                      decoration: InputDecoration(
                        labelText: 'Server IP',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.dns, color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                      ),
                      style: const TextStyle(color: Colors.white),
                      validator: (value) => value!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.settings_ethernet, color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      validator: (value) => value!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Username Field
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.person, color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  filled: true,
                  fillColor: Colors.black,
                ),
                style: const TextStyle(color: Colors.white),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // Password Field
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  filled: true,
                  fillColor: Colors.black,
                ),
                style: const TextStyle(color: Colors.white),
                obscureText: !_isPasswordVisible,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // Private Key Field
              TextFormField(
                controller: _privateKeyController,
                decoration: InputDecoration(
                  labelText: 'Private Key (optional)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.key, color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  filled: true,
                  fillColor: Colors.black,
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                // No validator since it's optional
              ),
              const SizedBox(height: 24),
              // Connect Button
              Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: 48,
                        height: 48,
                        child: FloatingActionButton(
                          onPressed: _connect,
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.0),
                          ),
                          child: const Icon(Icons.check, size: 20),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 1;

  static final List<Widget> _widgetOptions = <Widget>[
    const EditorScreen(),
    const TerminalScreen(),
    const PreviewScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == 3) { // SSH button (moved from index 4 to 3)
      _showEndSessionDialog();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _showEndSessionDialog() {
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
              _disconnectAndGoToLogin();
            },
            icon: const Icon(Icons.check, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectAndGoToLogin() async {
    try {
      // Disconnect current SSH session
      await ref.read(ssh.sshServiceProvider.notifier).disconnect();
      
      // Show brief confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session ended', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      
      // Navigate to login screen after a brief delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      });
    } catch (e) {
      // Even if disconnect fails, still go to login
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            BottomNavigationBarItem(
              icon: Iconify(Mdi.chevron_up, color: Colors.white),
              label: 'SSH',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed, // Ensures all labels are visible
          enableFeedback: false, // Disable haptic feedback and reduce tap effects
        ),
      ),
    );
  }
}
