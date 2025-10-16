import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:xterm/xterm.dart';
import 'ssh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'liquid_glass_tab_bar.dart';

// Terminal Tab Model
class TerminalTab {
  final String id;
  final String name;
  final Terminal terminal;
  final TerminalService service;

  TerminalTab({
    required this.id,
    required this.name,
    required this.terminal,
    required this.service,
  });

  TerminalTab copyWith({
    String? id,
    String? name,
    Terminal? terminal,
    TerminalService? service,
  }) {
    return TerminalTab(
      id: id ?? this.id,
      name: name ?? this.name,
      terminal: terminal ?? this.terminal,
      service: service ?? this.service,
    );
  }
}

// Terminal Tabs State
class TerminalTabsState {
  final List<TerminalTab> tabs;
  final int activeTabIndex;

  TerminalTabsState({
    required this.tabs,
    required this.activeTabIndex,
  });

  TerminalTabsState copyWith({
    List<TerminalTab>? tabs,
    int? activeTabIndex,
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }

  TerminalTab? get activeTab =>
      tabs.isNotEmpty && activeTabIndex >= 0 && activeTabIndex < tabs.length
          ? tabs[activeTabIndex]
          : null;
}

// Terminal Tabs Provider
final terminalTabsProvider =
    StateNotifierProvider<TerminalTabsNotifier, TerminalTabsState>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final notifier = TerminalTabsNotifier(sshService, ref);

  // Add a robust listener to always create a tab after any connection
  ref.listen<SshService>(sshServiceProvider, (previous, next) {
    debugPrint('TerminalTabsProvider: SSH Service changed: isConnected=${next.isConnected}');
    if (next.isConnected) {
      notifier.createNewTab();
    }
  });

  return notifier;
});

// Terminal Tabs Notifier
class TerminalTabsNotifier extends StateNotifier<TerminalTabsState> {
  final SshService _sshService;
  final Ref _ref;
  static const int maxTabs = 5; // Maximum number of terminal tabs
  static const String _prefsTabsKey = 'terminal_tabs';
  static const String _prefsActiveTabKey = 'terminal_active_tab';
  bool _tabsRestored = false;

  TerminalTabsNotifier(this._sshService, this._ref)
      : super(TerminalTabsState(tabs: [], activeTabIndex: -1)) {
    _initializeFirstTab();
    _restoreTabsFromPrefs();

    _ref.listen<SshService>(sshServiceProvider, (previous, next) {
      if (next.isConnected && state.tabs.isEmpty) {
        createNewTab();
      }
    });
  }

  void _initializeFirstTab() {
    if (_sshService.isConnected) {
      createNewTab();
    }
  }

  Future<void> _saveTabsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final tabNames = state.tabs.map((t) => t.name).toList();
    await prefs.setStringList(_prefsTabsKey, tabNames);
    await prefs.setInt(_prefsActiveTabKey, state.activeTabIndex);
  }

  Future<void> _restoreTabsFromPrefs() async {
    if (_tabsRestored || state.tabs.isNotEmpty) return;
    _tabsRestored = true;
    final prefs = await SharedPreferences.getInstance();
    final tabNames = prefs.getStringList(_prefsTabsKey);
    final activeIndex = prefs.getInt(_prefsActiveTabKey) ?? -1;
    if (tabNames != null &&
        tabNames.isNotEmpty &&
        _sshService.isConnected) {
      final tabs = <TerminalTab>[];
      for (final name in tabNames) {
        final tabId = DateTime.now().millisecondsSinceEpoch.toString();
        final terminal = Terminal();
        final service = TerminalService(_sshService, terminal);
        tabs.add(
            TerminalTab(id: tabId, name: name, terminal: terminal, service: service));
      }
      state = TerminalTabsState(
          tabs: tabs, activeTabIndex: activeIndex.clamp(0, tabs.length - 1));
    }
  }

  void createNewTab() {
    // Check max tabs limit
    if (state.tabs.length >= maxTabs) {
      return; // Don't create more tabs if at limit
    }

    final tabId = DateTime.now().millisecondsSinceEpoch.toString();
    final tabName = '${state.tabs.length + 1}';
    final terminal = Terminal();
    final service = TerminalService(_sshService, terminal);

    final newTab = TerminalTab(
      id: tabId,
      name: tabName,
      terminal: terminal,
      service: service,
    );

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabIndex: state.tabs.length,
    );
    _saveTabsToPrefs();
  }

  void switchToTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
      _saveTabsToPrefs();
    }
  }

  void closeTab(int index) {
    if (state.tabs.length <= 1) return; // Don't close the last tab

    final tabs = List<TerminalTab>.from(state.tabs);
    final closedTab = tabs.removeAt(index);

    // Dispose the closed tab's service
    closedTab.service.dispose();

    // Adjust active tab index
    int newActiveIndex = state.activeTabIndex;
    if (index == state.activeTabIndex) {
      // If closing active tab, switch to previous tab or first tab
      newActiveIndex = index > 0 ? index - 1 : 0;
    } else if (index < state.activeTabIndex) {
      // If closing tab before active tab, adjust index
      newActiveIndex = state.activeTabIndex - 1;
    }

    state = state.copyWith(
      tabs: tabs,
      activeTabIndex: newActiveIndex,
    );
    _saveTabsToPrefs();
  }

  void renameTab(int index, String newName) {
    if (index >= 0 && index < state.tabs.length) {
      final tabs = List<TerminalTab>.from(state.tabs);
      tabs[index] = tabs[index].copyWith(name: newName);
      state = state.copyWith(tabs: tabs);
      _saveTabsToPrefs();
    }
  }

  @override
  void dispose() {
    // Dispose all terminal services
    for (final tab in state.tabs) {
      tab.service.dispose();
    }
    super.dispose();
  }
}

// TerminalService
class TerminalService {
  final SshService _sshService;
  final Terminal _terminal;
  dartssh2.SSHSession? _shellSession;
  StreamSubscription? _stdoutSubscription;

  TerminalService(this._sshService, this._terminal) {
    _initializeTerminal();
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      // Add a small delay to prevent echo in portrait mode
      Future.delayed(const Duration(milliseconds: 50), () {
        resize(width, height);
      });
    };

    _sshService.addListener(_onSshServiceChange);
  }

  void _onSshServiceChange() {
    if (_sshService.isConnected) {
      _startShell();
    }
  }

  void _initializeTerminal() {
    if (_sshService.isConnected) {
      debugPrint('DEBUG: Initializing terminal service');
      _startShell();
    }
  }

  Future<void> _startShell() async {
    debugPrint('DEBUG: _TerminalScreenState._startShell() - Attempting to start shell.');
    try {
      _shellSession = await _sshService.shell();
      if (_shellSession == null) {
        debugPrint('DEBUG: _TerminalScreenState._startShell() - Shell session is null.');
        return;
      }
      debugPrint('DEBUG: _TerminalScreenState._startShell() - Shell session obtained. Listening to stdout.');
      _stdoutSubscription = _shellSession!.stdout.listen((data) {
        final output = utf8.decode(data);
        _terminal.write(output);
      });
    } catch (e) {
      debugPrint('DEBUG: _TerminalScreenState._startShell() - Shell session error: $e');
    }
  }

  void writeToShell(String text) {
    if (_shellSession != null) {
      _shellSession!.write(utf8.encode(text));
    }
  }

  void resize(int width, int height) {
    _shellSession?.resizeTerminal(width, height);
  }



  void dispose() {
    _stdoutSubscription?.cancel();
    _shellSession?.close();
    _sshService.removeListener(_onSshServiceChange);
  }
}

// Terminal Tab Bar Widget
class TerminalTabBar extends ConsumerWidget {
  final bool hidePlusButton;
  
  const TerminalTabBar({super.key, this.hidePlusButton = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(terminalTabsProvider);
    final tabsNotifier = ref.read(terminalTabsProvider.notifier);

    return Container(
      height: 40,
      color: Colors.black, // Changed color to black
      child: Row(
        children: [
          // Tab buttons
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabsState.tabs.length; i++)
                    _buildTabButton(
                      context,
                      tabsState.tabs[i],
                      i,
                      i == tabsState.activeTabIndex,
                      () => tabsNotifier.switchToTab(i),
                      () => tabsNotifier.closeTab(i),
                    ),
                ],
              ),
            ),
          ),
          // New tab button (hide if liquid glass is supported)
          if (!hidePlusButton)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: tabsState.tabs.length < TerminalTabsNotifier.maxTabs
                    ? () => tabsNotifier.createNewTab()
                    : null,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.add,
                    color: tabsState.tabs.length < TerminalTabsNotifier.maxTabs
                        ? Colors.white
                        : Colors.grey[600],
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context,
    TerminalTab tab,
    int index,
    bool isActive,
    VoidCallback onTap,
    VoidCallback onClose,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent, // No background highlighting
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    tab.name,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey[400],
                      fontSize: isActive ? 14 : 12, // Larger font for active tab
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal, // Slightly bolder for active
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: isActive
                        ? 16
                        : 14, // Slightly larger close icon for active tab
                    color: isActive ? Colors.white : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Enhanced Terminal Widget with simplified keyboard handling
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final FocusNode _terminalFocus = FocusNode();
  final TextEditingController _terminalController = TextEditingController();

  // Track previous input for real-time sync
  String _previousInput = '';
  
  // Liquid glass state
  bool _liquidGlassSupported = false;
  bool _liquidGlassTabBarShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for SSH reconnect and restore/create tabs
    final sshService = ref.watch(sshServiceProvider);
    final tabsNotifier = ref.read(terminalTabsProvider.notifier);
    
    if (sshService.isConnected) {
      // Try to restore tabs first
      tabsNotifier._restoreTabsFromPrefs();
      
      // If still no tabs after a short delay, create one
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final currentState = ref.read(terminalTabsProvider);
          if (currentState.tabs.isEmpty && sshService.isConnected) {
            debugPrint('TerminalScreen: Auto-creating first tab');
            tabsNotifier.createNewTab();
          }
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Add listener to text controller for real-time button updates
    _terminalController.addListener(() {
      setState(() {
        // This will trigger a rebuild when text changes
      });
    });
    _terminalController.addListener(_handleInputChange);
    // Don't auto-focus on init - let user tap to show keyboard
    
    // Initialize liquid glass components
    _initLiquidGlassComponents();
  }
  
  Future<void> _initLiquidGlassComponents() async {
    _liquidGlassSupported = await LiquidGlassTabBar.isSupported();
    if (_liquidGlassSupported) {
      // Initialize liquid glass tab bar (includes plus button)
      await _initLiquidGlassTabBar();
    }
  }
  
  Future<void> _initLiquidGlassTabBar() async {
    // Set up callbacks for tab bar
    LiquidGlassTabBar.setCallbacks(
      onTabSelected: (index) {
        ref.read(terminalTabsProvider.notifier).switchToTab(index);
      },
      onTabClosed: (index) {
        ref.read(terminalTabsProvider.notifier).closeTab(index);
      },
      onNewTab: () {
        final tabsState = ref.read(terminalTabsProvider);
        if (tabsState.tabs.length < TerminalTabsNotifier.maxTabs) {
          ref.read(terminalTabsProvider.notifier).createNewTab();
        }
      },
    );
    
    // Show the tab bar with current tabs
    await _updateLiquidGlassTabBar();
    
    if (mounted) {
      setState(() {
        _liquidGlassTabBarShown = true;
      });
    }
  }
  
  Future<void> _updateLiquidGlassTabBar() async {
    if (!_liquidGlassSupported) return;
    
    final tabsState = ref.read(terminalTabsProvider);
    final tabs = tabsState.tabs.map((tab) => {
      'id': tab.id,
      'name': tab.name,
    }).toList();
    
    final canAddTab = tabsState.tabs.length < TerminalTabsNotifier.maxTabs;
    
    if (_liquidGlassTabBarShown) {
      await LiquidGlassTabBar.updateTabs(
        tabs: tabs,
        activeIndex: tabsState.activeTabIndex,
        canAddTab: canAddTab,
      );
    } else {
      await LiquidGlassTabBar.show(
        tabs: tabs,
        activeIndex: tabsState.activeTabIndex,
        canAddTab: canAddTab,
      );
    }
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    _terminalController.removeListener(_handleInputChange);
    _terminalController.dispose();
    
    // Hide liquid glass tab bar when leaving terminal screen
    if (_liquidGlassTabBarShown) {
      LiquidGlassTabBar.hide();
    }
    
    super.dispose();
  }

  void _handleInputChange() {
    final current = _terminalController.text;
    final terminalService = ref.read(terminalTabsProvider).activeTab?.service;
    if (terminalService == null) return;

    final oldLen = _previousInput.length;
    final newLen = current.length;

    if (newLen > oldLen) {
      // Characters added
      final added = current.substring(oldLen);
      terminalService.writeToShell(added);
    } else if (newLen < oldLen) {
      // Characters deleted (backspace)
      for (int i = 0; i < oldLen - newLen; i++) {
        terminalService.writeToShell('\x7f'); // DEL (backspace)
      }
    }
    _previousInput = current;
  }

  void _insertText(String text) {
    // Add text to terminal input
    final currentText = _terminalController.text;
    final newText = currentText + text;
    _terminalController.text = newText;

    // Move cursor to end
    _terminalController.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
  }

  void _sendControlSequence(String sequence) {
    // Send control sequences immediately to terminal (for ESC, CTRL, etc.)
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;

    final terminalService = activeTab.service;
    terminalService.writeToShell(sequence);
  }

  void _handleHistoryNavigation(String sequence) {
    // Simply send the arrow key sequence to terminal - let the shell handle history
    final terminalService = ref.read(terminalTabsProvider).activeTab?.service;
    if (terminalService == null) return;

    // Send arrow key directly to terminal (traditional terminal behavior)
    terminalService.writeToShell(sequence);
    
    // Clear our input field since terminal is handling the history
    _terminalController.clear();
    _previousInput = '';
  }

  void _hideKeyboard() {
    // Properly dismiss keyboard and remove focus
    _terminalFocus.unfocus();
    FocusScope.of(context).unfocus();

    // Clear any text selection
    _terminalController.selection = const TextSelection.collapsed(offset: 0);

    debugPrint('DEBUG: Keyboard hidden');
  }

  void _showKeyboard() {
    // Show keyboard by focusing the terminal
    _terminalFocus.requestFocus();
    debugPrint('DEBUG: Keyboard shown');
  }

  void _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
        // Clean the pasted text - remove newlines and format for terminal input
        String pasteText = clipboardData.text!.trim();

        // If it's a multi-line paste, just take the first line for safety
        if (pasteText.contains('\n')) {
          pasteText = pasteText.split('\n').first.trim();
        }

        // Add the text to our current input
        final currentText = _terminalController.text;
        final newText = currentText + pasteText;
        _terminalController.text = newText;

        // Move cursor to end
        _terminalController.selection = TextSelection.fromPosition(
          TextPosition(offset: newText.length),
        );

        debugPrint('DEBUG: Pasted text: "$pasteText"');
      }
    } catch (e) {
      debugPrint('Error pasting from clipboard: $e');
    }
  }

  void _copyCurrentInput() async {
    // Copy the current input text (what user is typing)
    final currentInput = _terminalController.text;

    if (currentInput.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: currentInput));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current input copied to clipboard',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
        debugPrint('DEBUG: Copied current input: "$currentInput"');
      } catch (e) {
        debugPrint('Error copying current input: $e');
      }
    } else {
      // If no current input, copy the last command from terminal output
      _copyLastCommand();
    }
  }

  void _copyLastCommand() async {
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;

    final terminal = activeTab.terminal;

    // Get the terminal content as string and find the last command
    final terminalContent = terminal.buffer.toString();
    final lines = terminalContent.split('\n');

    String content = '';
    for (int i = lines.length - 1; i >= 0; i--) {
      final lineText = lines[i].trim();
      if (lineText.isNotEmpty &&
          !lineText.startsWith('Last login:') &&
          lineText.contains('%')) {
        // Found a command line, extract the command part
        final parts = lineText.split('%');
        if (parts.length > 1) {
          content = parts.last.trim();
          break;
        }
      }
    }

    if (content.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Last command copied to clipboard',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
        debugPrint('DEBUG: Copied last command: "$content"');
      } catch (e) {
        debugPrint('Error copying last command: $e');
      }
    }
  }

  Widget _buildShortcutButton(String text, String sequence,
      {VoidCallback? onTap, Color? color}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: color ?? Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () => _insertText(sequence),
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

  Widget _buildCtrlButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show a popup with Ctrl combinations
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                insetPadding: const EdgeInsets.all(16),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: _ctrlCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = _ctrlCommands[index];
                        return _buildCtrlOption(cmd['command']!,
                            cmd['description']!, cmd['sequence']!);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
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

  // Ctrl commands list
  static const List<Map<String, String>> _ctrlCommands = [
    {
      'command': 'Ctrl+C',
      'description': 'Interrupt current command',
      'sequence': '\x03'
    },
    {
      'command': 'Ctrl+D',
      'description': 'End of file / Exit shell',
      'sequence': '\x04'
    },
    {
      'command': 'Ctrl+Z',
      'description': 'Suspend current process',
      'sequence': '\x1a'
    },
    {
      'command': 'Ctrl+L',
      'description': 'Clear screen',
      'sequence': '\x0c'
    },
  ];

  Widget _buildCtrlOption(
      String command, String description, String sequence) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _sendControlSequence(sequence);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[700]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGitButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show a popup with Git commands in two columns
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                insetPadding: const EdgeInsets.all(16),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: _gitCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = _gitCommands[index];
                        return _buildGitOption(
                            cmd['command']!, cmd['description']!);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
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

  // Git commands list
  static const List<Map<String, String>> _gitCommands = [
    {
      'command': 'git init',
      'description': 'Start a new Git repo in the current directory.'
    },
    {
      'command': 'git clone [url]',
      'description': 'Copy a remote repository to your server.'
    },
    {
      'command': 'git status',
      'description': 'See which files are changed, staged, or untracked.'
    },
    {
      'command': 'git add .',
      'description': 'Stage all changes for the next commit.'
    },
    {
      'command': 'git commit -m "message"',
      'description': 'Save staged changes with a message.'
    },
    {'command': 'git push', 'description': 'Upload commits to the remote repo.'},
    {
      'command': 'git pull',
      'description': 'Fetch and merge updates from the remote.'
    },
    {'command': 'git log', 'description': 'View the history of commits.'},
    {'command': 'git branch', 'description': 'List all local branches.'},
    {
      'command': 'git checkout [branch]',
      'description': 'Switch to a different branch.'
    },
    {
      'command': 'git checkout -b [new-branch]',
      'description': 'Create and switch to a new branch.'
    },
    {
      'command': 'git merge [branch]',
      'description': 'Merge another branch into the current one.'
    },
  ];

  Widget _buildGitOption(String command, String description) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _insertText(command);

        // Position cursor between quotes for commit message
        if (command.contains('"message"')) {
          final controller = _terminalController;
          final text = controller.text;
          final msgIndex = text.indexOf('"message"');
          if (msgIndex != -1) {
            controller.selection = TextSelection(
              baseOffset: msgIndex + 1,
              extentOffset: msgIndex + 8,
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[700]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sshService = ref.watch(sshServiceProvider);
    final tabsState = ref.watch(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    final orientation = MediaQuery.of(context).orientation;
    final isPortrait = orientation == Orientation.portrait;

    if (!sshService.isConnected) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                'Connect to your server to use terminal',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
        ],
      );
    }

    if (activeTab == null) {
      final sshService = ref.watch(sshServiceProvider);
      final isConnected = sshService.isConnected;
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.terminal, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              isConnected 
                ? 'No terminal tabs available'
                : 'Connect to SSH first',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (isConnected)
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(terminalTabsProvider.notifier).createNewTab();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Terminal Tab'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha:0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
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
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Terminal tab bar (hide if liquid glass is supported)
            if (!_liquidGlassSupported)
              TerminalTabBar(hidePlusButton: _liquidGlassSupported),
            
            // Add spacing for liquid glass tab bar
            if (_liquidGlassSupported) const SizedBox(height: 60),

            // Terminal area with single TextField overlay
            Expanded(
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    // Terminal display with proper TerminalView
                    GestureDetector(
                      onTap: () {
                        debugPrint('DEBUG: Terminal tapped - showing keyboard');
                        _showKeyboard();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TerminalView(
                          key: ValueKey('terminal_${activeTab.id}_${isPortrait ? 'portrait' : 'landscape'}'),
                          activeTab.terminal,
                          theme: TerminalTheme(
                            background: Colors.black,
                            foreground: Colors.white,
                            cursor: Colors.white,
                            selection: Colors.blue.withAlpha(128),
                            black: Colors.black,
                            red: Colors.red,
                            green: Colors.green,
                            yellow: Colors.yellow,
                            blue: Colors.blue,
                            magenta: Colors.purple,
                            cyan: Colors.cyan,
                            white: Colors.white,
                            brightBlack: Colors.black87,
                            brightRed: Colors.redAccent,
                            brightGreen: Colors.lightGreen,
                            brightYellow: Colors.yellowAccent,
                            brightBlue: Colors.lightBlue,
                            brightMagenta: Colors.pinkAccent,
                            brightCyan: Colors.cyanAccent,
                            brightWhite: Colors.white70,
                            searchHitBackground: Colors.white,
                            searchHitBackgroundCurrent: Colors.blue,
                            searchHitForeground: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Terminal input bar (bigger)
            Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 
                _terminalFocus.hasFocus 
                  ? 0 // No padding when keyboard is open (shortcuts will provide spacing)
                  : 50  // Increased padding when keyboard is closed (to clear nav bar)
              ),
              child: Container(
                width: double.infinity,
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12), // Increased padding
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _terminalController,
                        focusNode: _terminalFocus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16, // Increased font size
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type commands here...',
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 16), // Increased hint size
                          filled: true,
                          fillColor: Colors.black,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16), // Increased padding
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25), // Fully rounded
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(51), width: 1.2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25), // Fully rounded
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(51), width: 1.2),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25), // Fully rounded
                            borderSide: BorderSide(
                                color: Colors.white.withAlpha(102),
                                width: 1.8),
                          ),
                          prefixIcon: IconButton(
                            icon: const Icon(
                              CupertinoIcons.keyboard_chevron_compact_down,
                              color: Colors.white,
                              size: 24, // Increased icon size
                            ),
                            onPressed: () {
                              debugPrint('DEBUG: Hide keyboard icon pressed');
                              _hideKeyboard();
                            },
                            splashRadius: 20,
                          ),
                          suffixIcon: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 32, // Smaller button
                            height: 32, // Smaller button
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _terminalController.text.trim().isNotEmpty 
                                    ? Colors.blue.withAlpha(204) // Highlight when text available
                                    : Colors.white.withAlpha(51), // Dim when empty
                                width: 1.5,
                              ),
                              color: _terminalController.text.trim().isNotEmpty 
                                  ? Colors.blue.withAlpha(25) // Subtle background when text available
                                  : Colors.transparent, // Transparent when empty
                            ),
                            child: IconButton(
                              icon: Icon(
                                CupertinoIcons.arrow_up,
                                color: _terminalController.text.trim().isNotEmpty 
                                    ? Colors.blue // Blue when text available
                                    : Colors.white.withAlpha(102), // Dim when empty
                                size: 18, // Bigger icon relative to button
                              ),
                              onPressed: _terminalController.text.trim().isNotEmpty ? () {
                                final terminalService = activeTab.service;
                                // Always send Enter (return key) regardless of input content
                                terminalService.writeToShell('\r');
                                // Clear input and reset previous input
                                _terminalController.clear();
                                _previousInput = '';
                                // Hide keyboard for better UX
                                _hideKeyboard();
                              } : null, // Disabled when no text
                              splashRadius: 16, // Smaller splash radius
                            ),
                          ),
                        ),
                        onSubmitted: (value) {
                          final terminalService = activeTab.service;
                          // Always send Enter (return key) regardless of input content
                          terminalService.writeToShell('\r');
                          // Clear input and reset previous input
                          _terminalController.clear();
                          _previousInput = '';
                          // Hide keyboard for better UX
                          _hideKeyboard();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Keyboard shortcuts row (only show when keyboard is open)
            if (_terminalFocus.hasFocus) ...[
              Container(
                height: isPortrait ? 40 : 50,
                color: Colors.grey[900],
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      // Control shortcuts first
                      _buildShortcutButton('esc', '\x1b',
                          onTap: () => _sendControlSequence('\x1b')),

                      // Copy and Paste buttons
                      _buildShortcutButton('cpy', '', onTap: () {
                        debugPrint(
                            'DEBUG: Copy button pressed - copying current input');
                        _copyCurrentInput();
                      }),

                      _buildShortcutButton('pste', '', onTap: () {
                        debugPrint('DEBUG: Paste button pressed');
                        _pasteFromClipboard();
                      }),

                      _buildCtrlButton('ctrl'),

                      // Navigation shortcuts
                      _buildShortcutButton('↑', '\x1b[A',
                          onTap: () => _handleHistoryNavigation('\x1b[A')),
                      _buildShortcutButton('↓', '\x1b[B',
                          onTap: () => _handleHistoryNavigation('\x1b[B')),
                      _buildShortcutButton('←', '\x1b[D',
                          onTap: () => _sendControlSequence('\x1b[D')),
                      _buildShortcutButton('→', '\x1b[C',
                          onTap: () => _sendControlSequence('\x1b[C')),
                      _buildShortcutButton('tab', '\t'),

                      // Common symbols
                      _buildGitButton('git'),
                      _buildServerButton('srvr'),
                      _buildFlutterButton('fltr'),
                      _buildBackupButton('bkup'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildServerButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show a popup with Server commands in two columns
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                insetPadding: const EdgeInsets.all(16),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: _serverCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = _serverCommands[index];
                        return _buildServerOption(
                            cmd['command']!, cmd['description']!);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
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

  // Server commands list
  static const List<Map<String, String>> _serverCommands = [
    {
      'command': 'flutter run -d web-server --web-port=3000 --web-hostname=0.0.0.0',
      'description': 'Start Flutter web server accessible from mobile'
    },
    {
      'command': 'ssh -R 3000:localhost:3000 -N -f username@server-ip',
      'description': 'SSH reverse tunnel: server:3000 → Mac:3000 (edit IP)'
    },
    {
      'command': 'npm start',
      'description': 'Start Node.js development server'
    },
    {
      'command': 'npm run dev',
      'description': 'Start Node.js dev server (Vite/Next.js)'
    },
    {
      'command': 'yarn start',
      'description': 'Start Yarn development server'
    },
    {
      'command': 'yarn dev',
      'description': 'Start Yarn dev server (Vite/Next.js)'
    },
    {
      'command': 'npx serve -s build -p 3000',
      'description': 'Serve static build files on port 3000'
    },
    {
      'command': 'python -m http.server 8000',
      'description': 'Quick Python HTTP server for static files'
    },
    {
      'command': 'live-server --port=3000',
      'description': 'Live-reload server for static files'
    },
  ];

  Widget _buildServerOption(String command, String description) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _insertText(command);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[700]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show a popup with Backup commands matching git/server style
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                insetPadding: const EdgeInsets.all(16),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: _backupCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = _backupCommands[index];
                        return _buildBackupOption(
                            cmd['command']!, cmd['description']!);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
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

  Widget _buildFlutterButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            // Show a popup with Flutter commands
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                insetPadding: const EdgeInsets.all(16),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 2.5,
                      ),
                      itemCount: _flutterCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = _flutterCommands[index];
                        return _buildFlutterOption(
                            cmd['command']!, cmd['description']!);
                      },
                    ),
                  ),
                ),
              ),
            );
          },
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

  // Backup commands list
  static const List<Map<String, String>> _backupCommands = [
    {
      'command': 'cp -r . ../project_name_backup',
      'description': 'Create backup in parent directory'
    },
    {
      'command': 'tar -czf ../project_backup.tar.gz .',
      'description': 'Create compressed backup archive'
    },
    {
      'command': 'rsync -av . ../project_backup/',
      'description': 'Sync backup with rsync'
    },
    {
      'command': 'zip -r ../project_backup.zip . -x "node_modules/*" ".git/*"',
      'description': 'Create zip backup (exclude common folders)'
    },
  ];

  Widget _buildBackupOption(String command, String description) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _insertText(command);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[700]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Flutter commands list
  static const List<Map<String, String>> _flutterCommands = [
    {
      'command': 'flutter run',
      'description': 'Run the Flutter app on connected device'
    },
    {
      'command': 'flutter run -d web-server --web-port=3000 --web-hostname=0.0.0.0',
      'description': 'Run Flutter web app accessible from mobile'
    },
    {
      'command': 'flutter build web',
      'description': 'Build Flutter app for web deployment'
    },
    {
      'command': 'flutter build apk',
      'description': 'Build Android APK'
    },
    {
      'command': 'flutter build ios',
      'description': 'Build iOS app (requires Xcode)'
    },
    {
      'command': 'flutter pub get',
      'description': 'Get dependencies from pubspec.yaml'
    },
    {
      'command': 'flutter pub add',
      'description': 'Add a new dependency (add package name)'
    },
    {
      'command': 'flutter clean',
      'description': 'Clean build cache and artifacts'
    },
    {
      'command': 'flutter doctor',
      'description': 'Check Flutter installation and setup'
    },
    {
      'command': 'flutter devices',
      'description': 'List connected devices'
    },
    {
      'command': 'flutter create new_project',
      'description': 'Create a new Flutter project'
    },
    {
      'command': 'flutter analyze',
      'description': 'Analyze Dart code for issues'
    },
  ];

  Widget _buildFlutterOption(String command, String description) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _insertText(command);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[700]!, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}