import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart' as wv;
import 'dart:async';
import 'ssh.dart';
import 'liquid_glass_play_button.dart';
import 'liquid_glass_nav.dart';

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
  bool? _liquidGlassSupported; // null until checked
  bool _liquidGlassPlayButtonShown = false;

  @override
  void initState() {
    super.initState();
    _portController.addListener(() {
      ref.read(previewPortProvider.notifier).state = _portController.text;
    });
    
    // Initialize liquid glass play button
    _initLiquidGlassPlayButton();
  }
  
  Future<void> _initLiquidGlassPlayButton() async {
    final supported = await LiquidGlassPlayButton.isSupported();
    setState(() {
      _liquidGlassSupported = supported;
    });
    
    if (supported) {
      // Set up callback for play button taps
      LiquidGlassPlayButton.setOnPlayButtonTappedCallback(() {
        _checkServerAndLoad();
      });
      
      // Show the play button
      final shown = await LiquidGlassPlayButton.show(isLoading: _isLoading);
      
      if (shown && mounted) {
        setState(() {
          _liquidGlassPlayButtonShown = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    _customUrlController.dispose();
    
    // Hide liquid glass play button when leaving preview screen
    if (_liquidGlassPlayButtonShown) {
      LiquidGlassPlayButton.hide();
    }
    
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
    
    // Update liquid glass button state
    if (_liquidGlassPlayButtonShown) {
      await LiquidGlassPlayButton.updateState(isLoading: true);
    }

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
      
      // Hide Liquid Glass elements when preview becomes active
      if (_liquidGlassPlayButtonShown) {
        await LiquidGlassPlayButton.hide();
      }
      await LiquidGlassNav.hide();
    } catch (e) {
      setState(() => _errorMessage = 'Error checking server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        // Update liquid glass button state
        if (_liquidGlassPlayButtonShown) {
          await LiquidGlassPlayButton.updateState(isLoading: false);
        }
      }
    }
  }

  void _stopPreview() async {
    ref.read(previewUrlProvider.notifier).state = null;
    setState(() => _errorMessage = null);
    
    // Show Liquid Glass elements again when preview stops
    if (_liquidGlassPlayButtonShown) {
      await LiquidGlassPlayButton.show(isLoading: false);
    }
    await LiquidGlassNav.show();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Preview stopped', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 200,
            left: 20,
            right: 20,
          ),
        ),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final previewUrl = ref.watch(previewUrlProvider);
    final sshService = ref.watch(sshServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: _buildPreviewContent(previewUrl, sshService.isConnected),
    );
  }

  Widget _buildPreviewContent(String? previewUrl, bool isConnected) {
    if (!isConnected) {
      return const SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Connect to your server to use preview',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (previewUrl == null) {
      return SafeArea(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Port and Custom URL input sections in separate rows
              SizedBox(
                width: 400,
                child: Column(
                  children: [
                    // Port field (top row)
                    TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        hintText: '3000',
                        hintStyle: const TextStyle(color: Colors.white70),
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
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    // Custom URL field (bottom row)
                    TextField(
                      controller: _customUrlController,
                      decoration: InputDecoration(
                        labelText: 'Custom URL (optional)',
                        labelStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16),
                        hintText: 'https://example.com',
                        hintStyle: const TextStyle(color: Colors.white70),
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
                '1. Use "srvr" button to start web server\n2. Enter port (default 3000) or custom URL\n3. Tap play to preview your web app!\n\nWorks with: React, Vue, Next.js, Vite, static sites',
                style: TextStyle(
                  color: Colors.grey, 
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),
              
              // Centered, larger play button (only show if liquid glass is explicitly not supported)
              if (_liquidGlassSupported == false)
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
              if (_liquidGlassSupported == false) const SizedBox(height: 24),
              if (_liquidGlassSupported == true) const SizedBox(height: 100), // Extra space when using liquid glass button
              // Remove the examples section completely
            ],
          ),
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
    
    // Use edge-to-edge mode (status bar visible but translucent)
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: [],
    );
    
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
  void dispose() {
    // Restore status bar when leaving preview
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // WebView or Error
        Expanded(
          child: _loadError != null
              ? SafeArea(
                  child: Center(
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
                  ),
                )
              : SafeArea(
                  bottom: false, // Allow bottom bar to extend to edge
                  child: wv.WebViewWidget(controller: _controller),
                ),
        ),
        // URL bar at bottom
        Container(
          padding: const EdgeInsets.only(
            left: 20,
            right: 6,
            top: 4,
            bottom: 4,
          ),
          decoration: const BoxDecoration(
            color: Colors.black,
            border: Border(
              top: BorderSide(color: Colors.white24, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.link, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.url,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoading) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.2),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.white),
                      onPressed: widget.onStop,
                      tooltip: 'Cancel',
                      padding: const EdgeInsets.all(0.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 14, color: Colors.white),
                      onPressed: () async {
                        if (await _controller.canGoBack()) {
                          _controller.goBack();
                        }
                      },
                      tooltip: 'Back',
                      padding: const EdgeInsets.all(0.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 14, color: Colors.white),
                      onPressed: () async {
                        if (await _controller.canGoForward()) {
                          _controller.goForward();
                        }
                      },
                      tooltip: 'Forward',
                      padding: const EdgeInsets.all(0.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    ),
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
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
} 