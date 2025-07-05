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
      
      // Check if server is running on the port
      final portCheck = await sshService.runCommandLenient(
        'curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/ 2>/dev/null || echo "0"'
      );
      
      if (portCheck?.trim() != "200") {
        setState(() => _errorMessage = 'No server found on port $port. Please start your development server first.\n\nExample: flutter run -d web-server --web-port=$port');
        return;
      }

      // Server is running - load the localhost URL
      final url = 'http://localhost:$port';
      ref.read(previewUrlProvider.notifier).state = url;
      setState(() => _errorMessage = null);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loading preview from $url'),
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
        );
      }
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
                if (!sshService.isConnected)
                  const Icon(Icons.wifi_off, color: Colors.grey),
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
            Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Not connected to SSH',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Connect to your server to use preview',
              style: TextStyle(color: Colors.grey, fontSize: 14),
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
              // Custom URL input section - always visible
              SizedBox(
                width: 300,
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
              const SizedBox(height: 16),
              
              // Localhost input section
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: 'localhost',
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

              const SizedBox(height: 24),
              
              // Play button
              IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.play_arrow, color: Colors.white, size: 48),
                onPressed: _isLoading ? null : _checkServerAndLoad,
                tooltip: 'Start Preview',
              ),
              
              const SizedBox(height: 32),
              
              // Instructions
              const Text(
                '1. Start your dev server in Terminal',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                '2. Enter port number above & tap play',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                '3. View your UI live!',
                style: TextStyle(color: Colors.grey, fontSize: 14),
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
      ..setNavigationDelegate(
        wv.NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadError = null;
            });
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (wv.WebResourceError error) {
            setState(() {
              _isLoading = false;
              _loadError = 'Failed to load: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // URL bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          color: Colors.grey[900],
          child: Row(
            children: [
              const Icon(Icons.link, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.url,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _loadError = null;
                        });
                        _controller.reload();
                      },
                      tooltip: 'Refresh',
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                      onPressed: widget.onStop,
                      tooltip: 'Stop Preview',
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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