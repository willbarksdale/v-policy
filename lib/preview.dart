import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ============================================================================
// LIQUID GLASS - Preview Components (Native iOS)
// ============================================================================

/// Play button for preview screen URL loading
class LiquidGlassPlayButton {
  static const MethodChannel _channel = MethodChannel('liquid_glass_play_button');
  
  static Future<bool> isSupported() async => true;
  
  static Future<bool> show({required bool isLoading}) async {
    try {
      final bool? result = await _channel.invokeMethod('enableNativeLiquidGlassPlayButton', {'isLoading': isLoading});
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
      final bool? result = await _channel.invokeMethod('updatePlayButtonState', {'isLoading': isLoading});
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating play button state: $e');
      return false;
    }
  }
  
  static void setOnPlayButtonTappedCallback(VoidCallback callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPlayButtonTapped') callback();
    });
  }
}

/// URL bar for web preview navigation
class LiquidGlassURLBar {
  static const _channel = MethodChannel('liquid_glass_url_bar');
  
  static Function()? _onBackTapped;
  static Function()? _onForwardTapped;
  static Function()? _onCloseTapped;
  static Function()? _onRefreshTapped;
  static Function(String)? _onURLSubmitted;
  
  static Future<bool> isSupported() async {
    try {
      final bool result = await _channel.invokeMethod('isLiquidGlassSupported');
      return result;
    } catch (e) {
      debugPrint('Error checking Liquid Glass support: $e');
      return false;
    }
  }
  
  static Future<bool> show({
    required String url,
    required bool canGoBack,
    required bool canGoForward,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('show', {
        'url': url,
        'canGoBack': canGoBack,
        'canGoForward': canGoForward,
      });
      return result;
    } catch (e) {
      debugPrint('Error showing Liquid Glass URL bar: $e');
      return false;
    }
  }
  
  static Future<bool> hide() async {
    try {
      final bool result = await _channel.invokeMethod('hide');
      return result;
    } catch (e) {
      debugPrint('Error hiding Liquid Glass URL bar: $e');
      return false;
    }
  }
  
  static Future<bool> updateState({
    String? url,
    bool? canGoBack,
    bool? canGoForward,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('updateState', {
        if (url != null) 'url': url,
        if (canGoBack != null) 'canGoBack': canGoBack,
        if (canGoForward != null) 'canGoForward': canGoForward,
      });
      return result;
    } catch (e) {
      debugPrint('Error updating Liquid Glass URL bar state: $e');
      return false;
    }
  }
  
  static void setCallbacks({
    required Function() onBackTapped,
    required Function() onForwardTapped,
    required Function() onCloseTapped,
    required Function() onRefreshTapped,
    required Function(String) onURLSubmitted,
  }) {
    _onBackTapped = onBackTapped;
    _onForwardTapped = onForwardTapped;
    _onCloseTapped = onCloseTapped;
    _onRefreshTapped = onRefreshTapped;
    _onURLSubmitted = onURLSubmitted;
    
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBackTapped':
          _onBackTapped?.call();
          break;
        case 'onForwardTapped':
          _onForwardTapped?.call();
          break;
        case 'onCloseTapped':
          _onCloseTapped?.call();
          break;
        case 'onRefreshTapped':
          _onRefreshTapped?.call();
          break;
        case 'onURLSubmitted':
          final url = call.arguments['url'] as String?;
          if (url != null) _onURLSubmitted?.call(url);
          break;
      }
    });
  }
}

/// Simple WebView screen for previewing the user's running dev server
class WebPreviewScreen extends StatefulWidget {
  final String url;
  final String hostIp;
  
  const WebPreviewScreen({
    super.key,
    required this.url,
    required this.hostIp,
  });

  @override
  State<WebPreviewScreen> createState() => _WebPreviewScreenState();
}

class _WebPreviewScreenState extends State<WebPreviewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _canGoBack = false;
  bool _canGoForward = false;
  late String _currentURL;

  @override
  void initState() {
    super.initState();
    _currentURL = widget.url; // Initialize with the starting URL
    _initWebView();
    _initLiquidGlassURLBar();
  }
  
  @override
  void dispose() {
    LiquidGlassURLBar.hide();
    super.dispose();
  }
  
  Future<void> _initLiquidGlassURLBar() async {
    // Set up callbacks
    LiquidGlassURLBar.setCallbacks(
      onBackTapped: () async {
        if (_canGoBack) {
          await _controller.goBack();
        }
      },
      onForwardTapped: () async {
        if (_canGoForward) {
          await _controller.goForward();
        }
      },
      onCloseTapped: () {
        Navigator.of(context).pop();
      },
      onRefreshTapped: () async {
        // Reload the current page
        await _controller.reload();
      },
      onURLSubmitted: (url) {
        var formattedUrl = url;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          formattedUrl = 'http://$url';
        }
        
        // Update current URL and load the request
        setState(() {
          _currentURL = formattedUrl;
        });
        _controller.loadRequest(Uri.parse(formattedUrl));
        
        // Update the URL bar to show the new URL
        LiquidGlassURLBar.updateState(
          url: formattedUrl,
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
        );
      },
    );
    
    // Show the URL bar
    await LiquidGlassURLBar.show(
      url: _currentURL,
      canGoBack: _canGoBack,
      canGoForward: _canGoForward,
    );
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Allow http and https URLs to load in the WebView
            if (request.url.startsWith('http://') || request.url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            
            // For all other schemes (mailto:, tel:, itms-apps:, etc.), 
            // prevent WebView navigation and let iOS handle it
            debugPrint('🔗 External URL detected: ${request.url}');
            return NavigationDecision.prevent;
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
            _updateNavigationState();
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _updateNavigationState();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to load: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }
  
  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
    
    // Update Liquid Glass URL bar (keep original URL, only update navigation state)
    await LiquidGlassURLBar.updateState(
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      // Don't update URL - keep it locked to the original widget.url
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Stack(
          children: [
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => _controller.reload(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.blue,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

