import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'ssh.dart';

// Terminal Tab Model
class TerminalTab {
  final String id;
  final String name;
  final Terminal terminal;
  final TerminalServiceNotifier service;
  
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
    TerminalServiceNotifier? service,
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
final terminalTabsProvider = StateNotifierProvider<TerminalTabsNotifier, TerminalTabsState>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  return TerminalTabsNotifier(sshService);
});

// Terminal Tabs Notifier
class TerminalTabsNotifier extends StateNotifier<TerminalTabsState> {
  final SshService _sshService;
  static const int maxTabs = 5; // Maximum number of terminal tabs
  
  TerminalTabsNotifier(this._sshService) : super(TerminalTabsState(tabs: [], activeTabIndex: -1)) {
    _initializeFirstTab();
  }
  
  void _initializeFirstTab() {
    if (_sshService.isConnected) {
      createNewTab();
    }
  }
  
  void createNewTab() {
    // Check max tabs limit
    if (state.tabs.length >= maxTabs) {
      return; // Don't create more tabs if at limit
    }
    
    final tabId = DateTime.now().millisecondsSinceEpoch.toString();
    final tabName = 'Terminal ${state.tabs.length + 1}';
    final terminal = Terminal();
    final service = TerminalServiceNotifier.withTerminal(_sshService, terminal);
    
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
  }
  
  void switchToTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
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
  }
  
  void renameTab(int index, String newName) {
    if (index >= 0 && index < state.tabs.length) {
      final tabs = List<TerminalTab>.from(state.tabs);
      tabs[index] = tabs[index].copyWith(name: newName);
      state = state.copyWith(tabs: tabs);
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

// Keep the original provider for backward compatibility
final terminalServiceProvider = StateNotifierProvider<TerminalServiceNotifier, Terminal>((ref) {
  final tabsState = ref.watch(terminalTabsProvider);
  return tabsState.activeTab?.service ?? TerminalServiceNotifier(ref.watch(sshServiceProvider));
});

// TerminalService (now a StateNotifier)
class TerminalServiceNotifier extends StateNotifier<Terminal> {
  final SshService _sshService;
  SSHSession? _shellSession;

  TerminalServiceNotifier(this._sshService) : super(Terminal()) {
    _initializeTerminal();
  }
  
  // Constructor for existing terminal instance
  TerminalServiceNotifier.withTerminal(this._sshService, Terminal terminal) : super(terminal) {
    _initializeTerminal();
  }

  void _initializeTerminal() {
    if (_sshService.isConnected) {
      _startInteractiveShell();
    }
  }

  Future<void> _startInteractiveShell() async {
    if (_shellSession != null) {
      return; // Only start if not already started
    }

    // DON'T set onOutput - we handle input manually to avoid conflicts
    // state.onOutput = (data) { ... }; // REMOVED - this was causing conflicts!

    try {
      _shellSession = await _sshService.startShell();
      debugPrint('Shell session created successfully'); // Debug

      _shellSession!.stdout.listen((data) {
        final decoded = utf8.decode(data);
        // Remove debug logging for better performance
        state.write(decoded);
      });

      _shellSession!.stderr.listen((data) {
        final decoded = utf8.decode(data);
        // Remove debug logging for better performance
        state.write(decoded);
      });

      state.onResize = (cols, rows, pixelWidth, pixelHeight) {
        _shellSession?.resizeTerminal(cols, rows);
      };

      _shellSession?.resizeTerminal(state.viewWidth, state.viewHeight);
      debugPrint('Terminal resized to ${state.viewWidth}x${state.viewHeight}'); // Debug
      
      _updateCurrentDirectory(); // Update directory after shell starts
    } catch (e) {
      debugPrint('Error starting shell: $e'); // Debug
    }
  }

  Future<void> _updateCurrentDirectory() async {
    try {
      final currentPath = await _sshService.runCommand('pwd');
      if (currentPath != null) {
        // Note: We can't update the provider from here without a ref
        // This could be handled at a higher level if needed
        debugPrint('Current directory: ${currentPath.trim()}');
      }
    } catch (e) {
      debugPrint('Error updating current directory: $e');
    }
  }

  void writeToShell(String text) {
    // Send to SSH shell session for execution
    if (_shellSession != null) {
      _shellSession!.write(utf8.encode(text));
    } else {
      debugPrint('No active shell session to write to');
    }
  }

  Future<void> refreshTerminal() async {
    debugPrint('Refreshing terminal...'); // Debug
    
    // Close existing session
    _shellSession?.close();
    _shellSession = null;
    
    // Create fresh terminal
    state = Terminal();
    
    // Start new shell if connected
    if (_sshService.isConnected) {
      await _startInteractiveShell();
    }
  }

  Future<String?> runCommand(String command) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    return await _sshService.runCommand(command);
  }

  @override
  void dispose() {
    _shellSession?.close();
    super.dispose();
  }
}

// Terminal Tab Bar Widget
class TerminalTabBar extends ConsumerWidget {
  const TerminalTabBar({super.key});

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
          // New tab button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: tabsState.tabs.length < TerminalTabsNotifier.maxTabs 
                  ? () => tabsNotifier.createNewTab()
                  : null,
              child: Container(
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
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, // Slightly bolder for active
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: isActive ? 16 : 14, // Slightly larger close icon for active tab
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
  String _previousText = ''; // Track previous text for backspace detection

  // Command history for easy reference
  final List<String> _commandHistory = [];
  
  void _addToHistory(String command) {
    if (command.trim().isNotEmpty && !_commandHistory.contains(command.trim())) {
      _commandHistory.add(command.trim());
      if (_commandHistory.length > 50) {
        _commandHistory.removeAt(0); // Keep only last 50 commands
      }
    }
  }





  @override
  void initState() {
    super.initState();
    // Don't auto-focus on init - let user tap to show keyboard
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  void _handleTextChange(String value) {
    debugPrint('DEBUG: Text changed from "$_previousText" to "$value"');
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;
    
    final terminalService = activeTab.service;
    
    if (value.length < _previousText.length) {
      // Text was removed - send backspace(s)
      int removedCount = _previousText.length - value.length;
      debugPrint('DEBUG: Sending $removedCount backspace(s)');
      for (int i = 0; i < removedCount; i++) {
        terminalService.writeToShell('\x7f'); // DEL character
      }
    } else if (value.length > _previousText.length) {
      // Text was added - send new characters
      String newChars = value.substring(_previousText.length);
      debugPrint('DEBUG: Sending new characters: "$newChars"');
      for (int i = 0; i < newChars.length; i++) {
        terminalService.writeToShell(newChars[i]);
      }
    }
    
    _previousText = value;
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
    
    // Handle the text change
    _handleTextChange(newText);
  }

  void _sendControlSequence(String sequence) {
    // Send control sequences immediately to terminal (for ESC, CTRL, etc.)
    final tabsState = ref.read(terminalTabsProvider);
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return;
    
    final terminalService = activeTab.service;
    terminalService.writeToShell(sequence);
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
        
        // Handle the text change to send to terminal
        _handleTextChange(newText);
        
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
            content: Text('Current input copied to clipboard', style: TextStyle(color: Colors.white)),
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
      if (lineText.isNotEmpty && !lineText.startsWith('Last login:') && lineText.contains('%')) {
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
            content: Text('Last command copied to clipboard', style: TextStyle(color: Colors.white)),
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

  Widget _buildShortcutButton(String text, String sequence, {VoidCallback? onTap, Color? color}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: color ?? Colors.grey[700],
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
        color: Colors.grey[600],
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
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _ctrlCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = _ctrlCommands[index];
                      return _buildCtrlOption(cmd['command']!, cmd['description']!, cmd['sequence']!);
                    },
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
    {'command': 'Ctrl+C', 'description': 'Interrupt current command', 'sequence': '\x03'},
    {'command': 'Ctrl+D', 'description': 'End of file / Exit shell', 'sequence': '\x04'},
    {'command': 'Ctrl+Z', 'description': 'Suspend current process', 'sequence': '\x1a'},
    {'command': 'Ctrl+L', 'description': 'Clear screen', 'sequence': '\x0c'},
  ];

  Widget _buildCtrlOption(String command, String description, String sequence) {
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
        color: Colors.grey[700],
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
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _gitCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = _gitCommands[index];
                      return _buildGitOption(cmd['command']!, cmd['description']!);
                    },
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
    {'command': 'git init', 'description': 'Start a new Git repo in the current directory.'},
    {'command': 'git clone [url]', 'description': 'Copy a remote repository to your server.'},
    {'command': 'git status', 'description': 'See which files are changed, staged, or untracked.'},
    {'command': 'git add .', 'description': 'Stage all changes for the next commit.'},
    {'command': 'git commit -m "message"', 'description': 'Save staged changes with a message.'},
    {'command': 'git push', 'description': 'Upload commits to the remote repo.'},
    {'command': 'git pull', 'description': 'Fetch and merge updates from the remote.'},
    {'command': 'git log', 'description': 'View the history of commits.'},
    {'command': 'git branch', 'description': 'List all local branches.'},
    {'command': 'git checkout [branch]', 'description': 'Switch to a different branch.'},
    {'command': 'git checkout -b [new-branch]', 'description': 'Create and switch to a new branch.'},
    {'command': 'git merge [branch]', 'description': 'Merge another branch into the current one.'},
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
    
    if (!sshService.isConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Connect to SSH to use terminal',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (activeTab == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No terminal tabs available',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Terminal tab bar
            const TerminalTabBar(),
            
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
                    
                    // Invisible TextField for input - covers entire terminal area
                    Positioned.fill(
                      child: TextField(
                        controller: _terminalController,
                        focusNode: _terminalFocus,
                        style: const TextStyle(color: Colors.transparent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        cursorColor: Colors.transparent,
                        maxLines: null,
                        expands: true,
                        textInputAction: TextInputAction.send,
                        onChanged: _handleTextChange,
                        onSubmitted: (value) {
                          // Handle return key - send carriage return to execute command
                          debugPrint('DEBUG: Return key pressed - sending \\r');
                          
                          // Add current input to history if it's not empty
                          if (value.trim().isNotEmpty) {
                            _addToHistory(value.trim());
                          }
                          
                          final terminalService = activeTab.service;
                          terminalService.writeToShell('\r');
                          
                          // Clear the text field and reset state
                          _terminalController.clear();
                          _previousText = '';
                          
                          // Keep focus for continued typing only if already focused
                          if (_terminalFocus.hasFocus) {
                            Future.microtask(() {
                              _terminalFocus.requestFocus();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Keyboard shortcuts row
            Container(
              height: 50,
              color: Colors.grey[900],
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    // Hide keyboard button
                    _buildShortcutButton('hide', '', onTap: () {
                      debugPrint('DEBUG: Hide keyboard button pressed');
                      _hideKeyboard();
                    }),
                    
                    // Copy and Paste buttons
                    _buildShortcutButton('cpy', '', onTap: () {
                      debugPrint('DEBUG: Copy button pressed - copying current input');
                      _copyCurrentInput();
                    }),
                    
                    _buildShortcutButton('pste', '', onTap: () {
                      debugPrint('DEBUG: Paste button pressed');
                      _pasteFromClipboard();
                    }),
                    
                    // Navigation shortcuts
                    _buildShortcutButton('↑', '\x1b[A', onTap: () => _sendControlSequence('\x1b[A')),
                    _buildShortcutButton('↓', '\x1b[B', onTap: () => _sendControlSequence('\x1b[B')),
                    _buildShortcutButton('←', '\x1b[D', onTap: () => _sendControlSequence('\x1b[D')),
                    _buildShortcutButton('→', '\x1b[C', onTap: () => _sendControlSequence('\x1b[C')),
                    _buildShortcutButton('tab', '\t'),
                    
                    // Control shortcuts
                    _buildShortcutButton('esc', '\x1b', onTap: () => _sendControlSequence('\x1b')),
                    _buildCtrlButton('ctrl'),
                    
                    // Common symbols
                    _buildShortcutButton('/', '/'),
                    _buildShortcutButton('.', '.'),
                    _buildShortcutButton('~', '~'),
                    _buildShortcutButton('-', '-'),
                    _buildShortcutButton('|', '|'),
                    _buildShortcutButton('>', '>'),
                    _buildShortcutButton('<', '<'),
                    _buildShortcutButton('\\', '\\'),
                    _buildShortcutButton(r'$', r'$'),
                    _buildGitButton('git'),
                    _buildServerButton('srvr'),
                    _buildBackupButton('bkup'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerButton(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: Colors.grey[700],
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
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _serverCommands.length,
                    itemBuilder: (context, index) {
                      final cmd = _serverCommands[index];
                      return _buildServerOption(cmd['command']!, cmd['description']!);
                    },
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
    {'command': 'flutter run -d web-server --web-port=3000', 'description': 'Start Flutter web server on port 3000'},
    {'command': 'npm start', 'description': 'Start Node.js development server'},
    {'command': 'npm run dev', 'description': 'Start Node.js dev server (Vite/Next.js)'},
    {'command': 'yarn start', 'description': 'Start Yarn development server'},
    {'command': 'yarn dev', 'description': 'Start Yarn dev server (Vite/Next.js)'},
    {'command': 'python -m http.server 8000', 'description': 'Start Python HTTP server on port 8000'},
    {'command': 'serve -s build', 'description': 'Serve static files from build directory'},
    {'command': 'serve -s dist', 'description': 'Serve static files from dist directory'},
    {'command': 'php -S localhost:8000', 'description': 'Start PHP built-in server on port 8000'},
    {'command': 'live-server --port=3000', 'description': 'Start live-server with auto-reload'},
    {'command': 'http-server -p 8080', 'description': 'Start http-server on port 8080'},
    {'command': 'npx serve -s build -l 3000', 'description': 'Serve build directory using npx'},
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
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            _insertBackupCommand();
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

  void _insertBackupCommand() {
    // Show backup options dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Backup Project', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _insertText('cp -r . ../project_name_backup');
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Backup command inserted!', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.black,
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Creates a backup in the parent directory',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'cp -r . ../project_name_backup',
                      style: TextStyle(color: Colors.green, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}