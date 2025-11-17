import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'ssh.dart';
import 'tmux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'liquid_glass.dart';

// Terminal Tab Model (backed by tmux windows or fallback shell session)
class TerminalTab {
  final String id;
  final String name;
  final Terminal terminal;
  final int tmuxWindowId; // -1 for non-tmux tabs
  final dartssh2.SSHSession? shellSession; // For fallback mode

  TerminalTab({
    required this.id,
    required this.name,
    required this.terminal,
    required this.tmuxWindowId,
    this.shellSession,
  });

  TerminalTab copyWith({String? name}) {
    return TerminalTab(
      id: id,
      name: name ?? this.name,
      terminal: terminal,
      tmuxWindowId: tmuxWindowId,
      shellSession: shellSession,
    );
  }
}

// Terminal State
class TerminalTabsState {
  final List<TerminalTab> tabs;
  final int activeTabIndex;
  final bool tmuxReady;
  final bool fallbackMode; // Using basic terminal without tmux
  final String? statusMessage;

  TerminalTabsState({
    required this.tabs,
    required this.activeTabIndex,
    this.tmuxReady = false,
    this.fallbackMode = false,
    this.statusMessage,
  });

  TerminalTabsState copyWith({
    List<TerminalTab>? tabs,
    int? activeTabIndex,
    bool? tmuxReady,
    bool? fallbackMode,
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      tmuxReady: tmuxReady ?? this.tmuxReady,
      fallbackMode: fallbackMode ?? this.fallbackMode,
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
  final tmuxService = TmuxService(sshService);
  
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
  final SshService _sshService;
  final TmuxService _tmuxService;
  static const int maxTabs = 3;
  
  StreamSubscription? _tmuxEventsSubscription;
  bool _isInitializing = false;

  TerminalTabsNotifier(this._sshService, this._tmuxService)
      : super(TerminalTabsState(tabs: [], activeTabIndex: -1)) {
    // Listen to tmux events
    _tmuxEventsSubscription = _tmuxService.events.listen(_handleTmuxEvent);
  }
  
  void _handleTmuxEvent(TmuxEvent event) {
    debugPrint('📨 Handling tmux event: ${event.runtimeType}');
    
    if (event is TmuxWindowCreated) {
      // Create a tab for the new window
      debugPrint('🪟 Window created event: ${event.window.id}');
      _createTabForWindow(event.window.id);
    } else if (event is TmuxOutput) {
      // Find the tab for this window and update its terminal
      try {
        final tab = state.tabs.firstWhere(
          (t) => t.tmuxWindowId == event.windowId,
        );
        tab.terminal.write(event.output);
      } catch (e) {
        debugPrint('No tab found for window ${event.windowId}');
      }
    } else if (event is TmuxError) {
      debugPrint('❌ tmux error event: ${event.message}');
      state = state.copyWith(statusMessage: 'Error: ${event.message}');
    }
  }

  Future<void> initializeTmux() async {
    if (_isInitializing || _tmuxService.isInitialized) {
      debugPrint('tmux already initializing or initialized');
      return;
    }
    
    _isInitializing = true;
    state = state.copyWith(statusMessage: 'Checking tmux...');
    debugPrint('🔍 Checking tmux installation...');
    
    // Load cached tmux info first
    await _tmuxService.loadCachedTmuxInfo();
    
    try {
      // Add timeout to prevent infinite loading
      final checkResult = await _tmuxService.checkTmuxInstalled()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('⏱️ tmux check timed out, assuming not installed');
        return TmuxCheckResult.notInstalledUnknown;
      });
      
      debugPrint('📋 tmux check result: $checkResult');
      
      if (checkResult == TmuxCheckResult.installed) {
        // tmux is ready, initialize it
        debugPrint('✅ tmux found, initializing...');
        state = state.copyWith(statusMessage: 'Initializing persistent terminal...');
        
        final success = await _tmuxService.initialize()
            .timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint('⏱️ tmux initialization timed out');
          return false;
        });
        
        debugPrint('🎯 tmux initialize result: $success');
        
        if (success) {
          debugPrint('✅ tmux initialized successfully');
          // The first tab will be created automatically by the TmuxWindowCreated event
          state = state.copyWith(
            tmuxReady: true,
            statusMessage: 'tmux_success', // Special flag for success state
          );
          
          // Clear success message after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            debugPrint('⏰ Auto-dismissing tmux success banner');
            if (state.statusMessage == 'tmux_success') {
              state = state.copyWith(statusMessage: null);
            }
          });
        } else {
          debugPrint('❌ Failed to start tmux session, falling back to basic terminal');
          // Fall back to basic terminal if tmux fails
          state = state.copyWith(
            fallbackMode: true,
            statusMessage: 'tmux_not_installed:notInstalledUnknown',
          );
          await createFallbackTerminal();
        }
      } else {
        // tmux not installed - enable fallback mode with basic terminal
        debugPrint('⚠️ tmux not installed, enabling fallback mode');
        state = state.copyWith(
          fallbackMode: true,
          statusMessage: 'tmux_not_installed:${checkResult.name}',
        );
        // Create a basic fallback terminal
        debugPrint('📝 Creating fallback terminal...');
        await createFallbackTerminal();
        debugPrint('✅ Fallback terminal creation completed');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error checking/initializing tmux: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // On any error, fall back to basic terminal
      debugPrint('🔄 Falling back to basic terminal due to error');
      state = state.copyWith(
        fallbackMode: true,
        statusMessage: 'tmux_not_installed:notInstalledUnknown',
      );
      
      try {
        await createFallbackTerminal();
      } catch (fallbackError) {
        debugPrint('❌ Fallback terminal creation also failed: $fallbackError');
        state = state.copyWith(statusMessage: 'Error: Failed to create terminal');
      }
    } finally {
      _isInitializing = false;
      debugPrint('🏁 initializeTmux finished, isInitializing: false');
    }
  }
  
  Future<void> installAndInitializeTmux(TmuxCheckResult osType) async {
    state = state.copyWith(statusMessage: 'Installing tmux...');
    
    try {
      final installed = await _tmuxService.installTmux(osType);
      
      if (installed) {
        // Now initialize
        state = state.copyWith(statusMessage: 'Initializing persistent terminal...');
        final success = await _tmuxService.initialize();
        
        if (success) {
          await _createTabForWindow(0);
          state = state.copyWith(
            tmuxReady: true,
            statusMessage: null,
          );
        } else {
          state = state.copyWith(
            statusMessage: 'Failed to start tmux session',
          );
        }
      } else {
        state = state.copyWith(
          statusMessage: 'Failed to install tmux. Please install manually.',
        );
      }
    } catch (e) {
      debugPrint('Error installing tmux: $e');
      state = state.copyWith(statusMessage: 'Installation error: $e');
    }
  }

  Future<void> _createTabForWindow(int windowId) async {
    final tabId = DateTime.now().millisecondsSinceEpoch.toString();
    final tabName = '${state.tabs.length + 1}';
    final terminal = Terminal(maxLines: 10000);

    final newTab = TerminalTab(
      id: tabId,
      name: tabName,
      terminal: terminal,
      tmuxWindowId: windowId,
    );

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabIndex: state.tabs.length,
    );
    
    debugPrint('Created tab for tmux window $windowId');
  }

  // Create a basic fallback terminal (no tmux)
  Future<void> createFallbackTerminal() async {
    debugPrint('📝 Creating fallback terminal (no tmux)...');
    
    try {
      final tabId = DateTime.now().millisecondsSinceEpoch.toString();
      debugPrint('  ↳ Tab ID: $tabId');
      
      final terminal = Terminal(maxLines: 10000);
      debugPrint('  ↳ Terminal object created');

      // Open a basic shell session
      debugPrint('  ↳ Opening SSH shell session...');
      final session = await _sshService.shell()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('  ⏱️ Shell session creation timed out');
        return null;
      });
      
      if (session == null) {
        debugPrint('  ❌ Failed to open shell for fallback terminal');
        state = state.copyWith(statusMessage: 'Failed to open shell');
        return;
      }
      
      debugPrint('  ✅ Shell session created');

      final newTab = TerminalTab(
        id: tabId,
        name: 'Terminal',
        terminal: terminal,
        tmuxWindowId: -1, // -1 indicates non-tmux tab
        shellSession: session,
      );
      
      debugPrint('  ↳ Tab object created');

      // Listen to session output
      session.stdout.listen(
        (data) {
          final output = utf8.decode(data);
          terminal.write(output);
        },
        onError: (error) {
          debugPrint('  ❌ Stdout error: $error');
        },
      );

      session.stderr.listen(
        (data) {
          final output = utf8.decode(data);
          terminal.write(output);
        },
        onError: (error) {
          debugPrint('  ❌ Stderr error: $error');
        },
      );
      
      debugPrint('  ↳ Output listeners attached');

      state = state.copyWith(
        tabs: [newTab],
        activeTabIndex: 0,
        statusMessage: null,
      );
      
      debugPrint('✅ Fallback terminal created successfully! Tab count: ${state.tabs.length}');
    } catch (e, stackTrace) {
      debugPrint('❌ Exception in createFallbackTerminal: $e');
      debugPrint('Stack trace: $stackTrace');
      state = state.copyWith(statusMessage: 'Error creating terminal: $e');
      rethrow;
    }
  }

  Future<void> createNewTab() async {
    debugPrint('🆕 createNewTab() called - Current tabs: ${state.tabs.length}');
    
    // Prevent exceeds max tabs
    if (state.tabs.length >= maxTabs) {
      debugPrint('⚠️ Already at max tabs ($maxTabs), ignoring createNewTab');
      return;
    }
    
    // In fallback mode, only allow one tab
    if (state.fallbackMode) {
      state = state.copyWith(statusMessage: 'Install tmux for multiple tabs');
      return;
    }

    if (state.tabs.length >= maxTabs) {
      state = state.copyWith(statusMessage: 'Maximum $maxTabs tabs reached');
      return;
    }

    if (!_tmuxService.isInitialized) {
      state = state.copyWith(statusMessage: 'tmux not ready');
      return;
    }

    final windowId = await _tmuxService.createWindow();
    
    if (windowId != null) {
      debugPrint('   ✅ Created window $windowId');
      await _createTabForWindow(windowId);
      state = state.copyWith(statusMessage: null);
    }
  }

  Future<void> switchToTab(int index) async {
    if (index >= 0 && index < state.tabs.length) {
      final tab = state.tabs[index];
      await _tmuxService.switchToWindow(tab.tmuxWindowId);
      state = state.copyWith(activeTabIndex: index);
    }
  }

  Future<void> closeTab(int index) async {
    if (state.tabs.length <= 1) {
      state = state.copyWith(statusMessage: 'Cannot close last tab');
      return;
    }

    final tab = state.tabs[index];
    await _tmuxService.closeWindow(tab.tmuxWindowId);
    
    final tabs = List<TerminalTab>.from(state.tabs);
    tabs.removeAt(index);

    int newActiveIndex = state.activeTabIndex;
    if (index <= state.activeTabIndex) {
      newActiveIndex = (state.activeTabIndex - 1).clamp(0, tabs.length - 1);
    }

    state = state.copyWith(
      tabs: tabs,
      activeTabIndex: newActiveIndex,
      statusMessage: null,
    );
  }
  
  Future<void> sendInput(String text) async {
    if (state.fallbackMode) {
      // Fallback mode: write directly to the shell session
      final activeTab = state.activeTab;
      if (activeTab?.shellSession != null) {
        activeTab!.shellSession!.write(utf8.encode(text));
      }
    } else {
      // tmux mode: use tmux service
      if (!_tmuxService.isInitialized) return;
      await _tmuxService.sendInput(text);
    }
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
  String _previousInput = '';
  bool _hasText = false;
  
  bool _liquidGlassTabBarShown = false;
  bool _liquidGlassTerminalInputShown = false;
  bool _nativeKeyboardVisible = false;  // Track native iOS keyboard state
  bool _isCreatingTab = false;  // Debounce flag for tab creation
  
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
    _loadCustomShortcuts();
    
    // Check if SSH is already connected and initialize terminal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sshService = ref.read(sshServiceProvider);
      final tabsState = ref.read(terminalTabsProvider);
      
      debugPrint('📱 Terminal screen initialized. SSH connected: ${sshService.isConnected}, tabs: ${tabsState.tabs.length}');
      
      if (sshService.isConnected && 
          tabsState.tabs.isEmpty && 
          !tabsState.tmuxReady && 
          !tabsState.fallbackMode) {
        debugPrint('🚀 SSH already connected, initializing terminal...');
        ref.read(terminalTabsProvider.notifier).initializeTmux();
      }
    });
    
    // Listen to tab changes and update Liquid Glass tab bar
    ref.listenManual(terminalTabsProvider, (previous, next) {
      if (_liquidGlassTabBarShown) {
        if (previous != null) {
          final tabCountChanged = previous.tabs.length != next.tabs.length;
          final activeIndexChanged = previous.activeTabIndex != next.activeTabIndex;
          
          if (tabCountChanged || activeIndexChanged) {
            debugPrint('📊 Tabs changed: count ${previous.tabs.length} → ${next.tabs.length}, active ${previous.activeTabIndex} → ${next.activeTabIndex}');
            // Update immediately - debounce is handled in onNewTab callback
            if (mounted) {
              _updateLiquidGlassTabBar();
            }
          }
        }
      }
    });
  }
  
  Future<void> _initLiquidGlassComponents() async {
    // Initialize Liquid Glass tab bar and terminal input (iOS 26+ only)
    await _initLiquidGlassTabBar();
    await _initLiquidGlassTerminalInput();
  }
  
  Future<void> _initLiquidGlassTabBar() async {
    LiquidGlassTabBar.setCallbacks(
      onTabSelected: (index) {
        ref.read(terminalTabsProvider.notifier).switchToTab(index);
      },
      onTabClosed: (index) {
        ref.read(terminalTabsProvider.notifier).closeTab(index);
      },
      onNewTab: () {
        // Simple debounce: check flag and return immediately if already creating
        if (_isCreatingTab) {
          debugPrint('⚠️ Tab creation already in progress, ignoring');
          return;
        }
        
        final tabsState = ref.read(terminalTabsProvider);
        if (tabsState.tabs.length >= TerminalTabsNotifier.maxTabs) {
          debugPrint('⚠️ Already at max tabs, ignoring');
          return;
        }
        
        // Set flag IMMEDIATELY before async call
        _isCreatingTab = true;
        debugPrint('🆕 Tab creation started, flag set');
        
        // Create tab
        ref.read(terminalTabsProvider.notifier).createNewTab();
        
        // Reset flag after 1 second (generous delay)
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _isCreatingTab = false;
            debugPrint('✅ Tab creation flag reset');
          }
        });
      },
    );
    
    await _updateLiquidGlassTabBar();
    
    if (mounted) {
      setState(() {
        _liquidGlassTabBarShown = true;
      });
    }
  }
  
  Future<void> _initLiquidGlassTerminalInput() async {
    // Initialize callbacks
    await LiquidGlassTerminalInput.initialize(
      onCommandSent: (text) {
        // Send command with newline
        _sendCommand('\r');
      },
      onInputChanged: (text) {
        // Sync text from native to Flutter controller
        if (_terminalController.text != text) {
          _terminalController.text = text;
          _previousInput = text;
          setState(() {
            _hasText = text.trim().isNotEmpty;
          });
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
      placeholder: 'Type commands here...',
    );
    
    if (shown && mounted) {
      setState(() {
        _liquidGlassTerminalInputShown = true;
      });
      debugPrint('✅ Liquid Glass terminal input shown');
    }
  }
  
  Future<void> _updateLiquidGlassTabBar() async {
    final tabsState = ref.read(terminalTabsProvider);
    final tabs = tabsState.tabs.map((tab) => {
      'id': tab.id,
      'name': tab.name,
    }).toList();
    
    final canAddTab = tabsState.tabs.length < TerminalTabsNotifier.maxTabs;
    
    debugPrint('🔄 Updating Liquid Glass tab bar: ${tabs.length} tabs, active: ${tabsState.activeTabIndex}, canAdd: $canAddTab');
    debugPrint('   Tabs: ${tabs.map((t) => t['name']).join(', ')}');
    
    if (_liquidGlassTabBarShown) {
      final result = await LiquidGlassTabBar.updateTabs(
        tabs: tabs,
        activeIndex: tabsState.activeTabIndex,
        canAddTab: canAddTab,
      );
      debugPrint('   Update result: $result');
    } else {
      final result = await LiquidGlassTabBar.show(
        tabs: tabs,
        activeIndex: tabsState.activeTabIndex,
        canAddTab: canAddTab,
      );
      debugPrint('   Show result: $result');
    }
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    _terminalController.dispose();
    if (_liquidGlassTabBarShown) {
      LiquidGlassTabBar.hide();
    }
    if (_liquidGlassTerminalInputShown) {
      LiquidGlassTerminalInput.hide();
    }
    super.dispose();
  }

  void _handleInputChange() {
    final current = _terminalController.text;
    final oldLen = _previousInput.length;
    final newLen = current.length;

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

    if (newLen > oldLen) {
      final added = current.substring(oldLen);
      ref.read(terminalTabsProvider.notifier).sendInput(added);
    } else if (newLen < oldLen) {
      for (int i = 0; i < oldLen - newLen; i++) {
        ref.read(terminalTabsProvider.notifier).sendInput('\x7f');
      }
    }

    _previousInput = current;
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
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;

    if (tabsState.fallbackMode && activeTab.shellSession != null) {
      // Fallback mode: write directly to shell session
      activeTab.shellSession!.write(utf8.encode('$command\r'));
    } else {
      // tmux mode
      ref.read(terminalTabsProvider.notifier).sendInput('$command\r');
    }
  }

  void _sendKeys(String sequence) {
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;

    if (tabsState.fallbackMode && activeTab.shellSession != null) {
      // Fallback mode: write directly to shell session
      activeTab.shellSession!.write(utf8.encode(sequence));
    } else {
      // tmux mode
      ref.read(terminalTabsProvider.notifier).sendInput(sequence);
    }
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

    // Show loading only if neither tmux nor fallback is ready AND we have no tabs
    if (!tabsState.tmuxReady && !tabsState.fallbackMode && activeTab == null) {
      // Regular loading state
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
              style: const TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // In fallback mode, show loading until tab is created
    if (tabsState.fallbackMode && activeTab == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Opening terminal...',
              style: TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // If we somehow have no active tab but should have one, show error
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

    // Update liquid glass tab bar when tabs change
    if (_liquidGlassTabBarShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateLiquidGlassTabBar();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Spacing for liquid glass tab bar (always present on iOS 26+)
            const SizedBox(height: 60),

            // Show tmux success banner
            if (tabsState.statusMessage == 'tmux_success')
              _buildSuccessBanner(),
            
            // Show tmux install banner if in fallback mode
            if (tabsState.fallbackMode && tabsState.statusMessage != null && 
                tabsState.statusMessage!.startsWith('tmux_not_installed:'))
              _buildTmuxBanner(ref, tabsState.statusMessage!),

            // Terminal display
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

            // Keyboard shortcuts - sits above input (Flutter or Liquid Glass)
            Padding(
              padding: EdgeInsets.only(
                bottom: _liquidGlassTerminalInputShown 
                  ? (_nativeKeyboardVisible ? 60 : 110)  // 60px when keyboard open, 110px when closed
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
                              _previousInput = '';
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
                    _previousInput = '';
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

  Widget _buildSuccessBanner() {
    return Container(
      color: Colors.green[700],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '✨ Persistent sessions enabled!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              ref.read(terminalTabsProvider.notifier).clearStatusMessage();
            },
            icon: const Icon(
              Icons.close,
              color: Colors.white,
              size: 20,
            ),
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildTmuxBanner(WidgetRef ref, String statusMessage) {
    final osTypeName = statusMessage.split(':')[1];
    final osType = TmuxCheckResult.values.firstWhere(
      (e) => e.name == osTypeName,
      orElse: () => TmuxCheckResult.notInstalledUnknown,
    );

    return Container(
      color: Colors.orange[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Install tmux for persistent sessions',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Type: ${_getTmuxInstallCommand(osType)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ref.read(terminalTabsProvider.notifier).initializeTmux();
            },
            icon: const Icon(
              CupertinoIcons.refresh,
              color: Colors.white,
              size: 20,
            ),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  String _getTmuxInstallCommand(TmuxCheckResult osType) {
    switch (osType) {
      case TmuxCheckResult.notInstalledUbuntu:
        return 'sudo apt-get install tmux';
      case TmuxCheckResult.notInstalledCentos:
        return 'sudo yum install tmux';
      case TmuxCheckResult.notInstalledMac:
        return 'brew install tmux';
      case TmuxCheckResult.notInstalledArch:
        return 'sudo pacman -S tmux';
      default:
        return 'tmux (see server docs)';
    }
  }

  Widget _buildShortcutButton(String text, String sequence, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () => _sendKeys(sequence),
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
