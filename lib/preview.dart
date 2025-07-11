import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv;
import 'dart:async';
import 'ssh.dart';

// Preview settings provider
final previewUrlProvider = StateProvider<String?>((ref) => null);
final previewPortProvider = StateProvider<String>((ref) => '3000');

// Preview Screen
class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key});

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  final _portController = TextEditingController(text: '3000');
  final _customUrlController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _portController.addListener(() {
      ref.read(previewPortProvider.notifier).state = _portController.text;
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _checkServerAndLoad() async {
    // Check if custom URL is provided first
    final customUrl = _customUrlController.text.trim();
    if (customUrl.isNotEmpty) {
      // Validate URL format
      if (!customUrl.startsWith('http://') && !customUrl.startsWith('https://')) {
        setState(() => _errorMessage = 'URL must start with http:// or https://');
        return;
      }
      
      ref.read(previewUrlProvider.notifier).state = customUrl;
      setState(() => _errorMessage = null);
      return;
    }

    // Fall back to localhost
    final port = _portController.text.trim();
    if (port.isEmpty) {
      setState(() => _errorMessage = 'Please enter a port number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sshService = ref.read(sshServiceProvider);
      
      // Use SSH server IP for preview
      final connectedIp = ref.read(connectedIpProvider);
      String serverHost = connectedIp ?? 'localhost';
      
      // For development: if connecting to localhost/127.0.0.1, 
      // try to get the actual network IP of the development machine
      if (serverHost == 'localhost' || serverHost == '127.0.0.1') {
        try {
          final networkIp = await sshService.runCommandLenient(
            'ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk \'{print \$2}\' || hostname -I | awk \'{print \$1}\''
          );
          if (networkIp != null && networkIp.trim().isNotEmpty && networkIp.trim() != 'NOT_FOUND') {
            serverHost = networkIp.trim();
            debugPrint('Using detected network IP: $serverHost');
          }
        } catch (e) {
          debugPrint('Failed to detect network IP: $e');
        }
      }
      
      // Check if server is running on the port with multiple methods
      bool serverFound = false;
      
      // Method 1: Check if port is listening
      final portListening = await sshService.runCommandLenient(
        'netstat -an | grep ":$port " | grep LISTEN || lsof -i :$port || echo "NOT_LISTENING"'
      );
      
      if (portListening != null && !portListening.contains('NOT_LISTENING')) {
        serverFound = true;
        debugPrint('Server detected via port check: $portListening');
      }
      
      // Method 2: Try HTTP request if port check passed
      if (serverFound) {
        final httpCheck = await sshService.runCommandLenient(
          'curl -s -m 3 -o /dev/null -w "%{http_code}" http://localhost:$port/ 2>/dev/null || echo "0"'
        );
        
        if (httpCheck?.trim() == "200") {
          debugPrint('Server confirmed via HTTP check');
        } else {
          debugPrint('Port listening but HTTP failed: $httpCheck');
          // Still proceed - server might be starting up
        }
      }
      
      if (!serverFound) {
        setState(() => _errorMessage = 'No server found on port $port. Please start your development server first.\n\nExample: flutter run -d web-server --web-port=$port --web-hostname=0.0.0.0');
        return;
      }

      // Server is running - use the SSH server IP instead of localhost
      final url = 'http://$serverHost:$port';
      
      // Alternative: Try SSH tunnel approach if direct connection fails
      // This creates a tunnel: SSH_SERVER:$port -> localhost:$port
      // So we can access via SSH server IP even if Mac is behind NAT
      
      // Test if the URL is accessible from the mobile device
      debugPrint('Testing URL accessibility: $url');
      try {
        final testResponse = await sshService.runCommandLenient(
          'curl -s -I "$url" | head -1 || echo "CURL_FAILED"'
        );
        debugPrint('URL test response: $testResponse');
        
        if (testResponse?.contains('CURL_FAILED') == true || testResponse?.contains('Connection refused') == true) {
          setState(() => _errorMessage = 'Server not accessible from mobile device.\n\nIf developing locally:\n• Use Custom URL: http://YOUR_MAC_IP:$port\n• Find your Mac IP: ifconfig | grep "inet "\n\nOr run: flutter run -d web-server --web-port=$port --web-hostname=0.0.0.0');
          return;
        }
      } catch (e) {
        debugPrint('URL test failed: $e');
      }
      
      ref.read(previewUrlProvider.notifier).state = url;
      setState(() => _errorMessage = null);
    } catch (e) {
      setState(() => _errorMessage = 'Error checking server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _stopPreview() {
    ref.read(previewUrlProvider.notifier).state = null;
    setState(() => _errorMessage = null);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preview stopped', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final previewUrl = ref.watch(previewUrlProvider);
    final sshService = ref.watch(sshServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header with wifi status only
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              bottom: 8,
            ),
            decoration: const BoxDecoration(
              color: Colors.black,
            ),
            child: Row(
              children: [
                const Spacer(),
              ],
            ),
          ),
          
          // Preview content
          Expanded(
            child: _buildPreviewContent(previewUrl, sshService.isConnected),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(String? previewUrl, bool isConnected) {
    if (!isConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Connect to your server to use preview',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (previewUrl == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Localhost and Custom URL input section on same row
              SizedBox(
                width: 320,
                child: Row(
                  children: [
                    // Localhost field (left side)
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: 'port',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '3000',
                          hintStyle: const TextStyle(color: Colors.white70),
                          isDense: true,
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
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Custom URL field (right side, slightly smaller)
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _customUrlController,
                        decoration: InputDecoration(
                          labelText: 'Custom URL (optional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'https://example.com',
                          hintStyle: const TextStyle(color: Colors.white70),
                          isDense: true,
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
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 32),
              
              // Instructions with consistent spacing like info screen
              const Text(
                '1. Start your dev server in Terminal:\n   flutter run -d web-server --web-hostname=0.0.0.0\n2. Enter port number above & tap play\n3. View your UI live!',
                style: TextStyle(
                  color: Colors.grey, 
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),
              
                            // Centered, larger play button (moved below instructions)
              SizedBox(
                width: 64,
                height: 64,
                child: _isLoading 
                  ? const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                  : FloatingActionButton(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      onPressed: _checkServerAndLoad,
                      child: const Icon(Icons.play_arrow, size: 28),
                    ),
              ),
              const SizedBox(height: 24),
              // Remove the examples section completely
            ],
          ),
        ),
      );
    }

    return PreviewWebView(url: previewUrl, onStop: _stopPreview);
  }
}

// WebView Widget
class PreviewWebView extends StatefulWidget {
  final String url;
  final VoidCallback onStop;

  const PreviewWebView({super.key, required this.url, required this.onStop});

  @override
  State<PreviewWebView> createState() => _PreviewWebViewState();
}

class _PreviewWebViewState extends State<PreviewWebView> {
  late wv.WebViewController _controller;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = wv.WebViewController()
      ..setJavaScriptMode(wv.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        wv.NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('WebView: Page started loading: $url');
            setState(() {
              _isLoading = true;
              _loadError = null;
            });
          },
          onPageFinished: (String url) {
            debugPrint('WebView: Page finished loading: $url');
            setState(() => _isLoading = false);
          },
          onWebResourceError: (wv.WebResourceError error) {
            debugPrint('WebView: Resource error: ${error.description} (${error.errorCode})');
            setState(() {
              _isLoading = false;
              _loadError = 'Failed to load: ${error.description}\nError code: ${error.errorCode}';
            });
          },
          onHttpError: (wv.HttpResponseError error) {
            debugPrint('WebView: HTTP error: ${error.response?.statusCode}');
            setState(() {
              _isLoading = false;
              _loadError = 'HTTP Error: ${error.response?.statusCode}';
            });
          },
          onNavigationRequest: (wv.NavigationRequest request) {
            debugPrint('WebView: Navigation request to: ${request.url}');
            return wv.NavigationDecision.navigate;
          },
        ),
      );
    
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // URL bar
        Container(
          padding: const EdgeInsets.only(left: 6, right: 6, top: 0, bottom: 0.5),
          decoration: const BoxDecoration(
            color: Colors.black,
            border: Border(
              bottom: BorderSide(color: Colors.white24, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.link, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.url,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.2),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 14, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _loadError = null;
                        });
                        _controller.reload();
                      },
                      tooltip: 'Refresh',
                      padding: const EdgeInsets.all(0.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.white),
                      onPressed: widget.onStop,
                      tooltip: 'Stop Preview',
                      padding: const EdgeInsets.all(0.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // WebView or Error
        Expanded(
          child: _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _loadError!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadError = null;
                          });
                          _controller.reload();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : wv.WebViewWidget(controller: _controller),
        ),
      ],
    );
  }
} 