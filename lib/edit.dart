import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/highlight.dart' as highlight;

import 'ssh.dart';

// File System Models and Providers
enum FileSystemEntityType { file, directory }

class FileSystemEntity {
  final String name;
  final String path;
  final FileSystemEntityType type;

  FileSystemEntity({
    required this.name,
    required this.path,
    required this.type,
  });
}

final currentDirectoryProvider = StateProvider<String>((ref) => '/');
final currentProjectPathProvider = StateProvider<String>((ref) => '');
final recentProjectsProvider = StateProvider<List<String>>((ref) => []);

// File Tree Models
class FileTreeNode {
  final String name;
  final String path;
  final bool isDirectory;
  final List<FileTreeNode> children;
  final int level;

  FileTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    List<FileTreeNode>? children,
    this.level = 0,
  }) : children = children ?? [];

  FileTreeNode copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    List<FileTreeNode>? children,
    int? level,
  }) {
    return FileTreeNode(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      children: children ?? this.children,
      level: level ?? this.level,
    );
  }
}

class FileTreeService {
  static List<FileTreeNode> parseFileList(String findOutput) {
    final lines = findOutput
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final Map<String, FileTreeNode> nodeMap = {};

    debugPrint('FileTree: Parsing ${lines.length} paths');

    // Remove leading "./" and normalize paths, preserving directory indicators
    final cleanPaths = <String>[];
    final directoryPaths = <String>{};
    
    for (final line in lines) {
      String path = line.trim();
      if (path.isEmpty || path == '.') continue;
      
      // Remove leading "./"
      if (path.startsWith('./')) {
        path = path.substring(2);
      }
      
      // Check if this is marked as a directory (ends with /)
      bool isDirectoryMarked = path.endsWith('/');
      if (isDirectoryMarked) {
        path = path.substring(0, path.length - 1);
        directoryPaths.add(path);
      }
      
      if (path.isNotEmpty) {
        cleanPaths.add(path);
      }
    }

    // Remove duplicates and sort
    final uniquePaths = cleanPaths.toSet().toList()..sort();
    debugPrint('FileTree: Clean paths (first 20): ${uniquePaths.take(20).toList()}');
    
    // Debug: Check specifically for lib directory files
    final libPaths = uniquePaths.where((path) => path.startsWith('lib/')).toList();
    debugPrint('FileTree: Found ${libPaths.length} lib directory paths: ${libPaths.take(10).toList()}');

    // Build all nodes with improved directory detection
    for (final path in uniquePaths) {
      final pathParts = path.split('/');

      // Build each part of the path
      String currentPath = '';
      for (int i = 0; i < pathParts.length; i++) {
        final part = pathParts[i];
        currentPath = i == 0 ? part : '$currentPath/$part';

        if (!nodeMap.containsKey(currentPath)) {
          // Enhanced directory detection:
          // 1. Explicitly marked as directory (ended with /)
          // 2. Any path starts with this path + "/"
          // 3. Intermediate path segments are always directories
          // 4. Check original lines for directory markers
          // 5. Known directory names (common Flutter directories)
          final isKnownDir = ['lib', 'android', 'ios', 'web', 'test', 'linux', 'windows', 'build', 'assets', '.dart_tool'].contains(part);
          
          final isDirectory = directoryPaths.contains(currentPath) ||
              uniquePaths.any((p) => p.startsWith('$currentPath/')) ||
              (i < pathParts.length - 1) ||
              lines.any((line) => line.trim() == './$currentPath/' || line.trim() == '$currentPath/') ||
              (i == 0 && isKnownDir); // Root level known directories

          final node = FileTreeNode(
            name: part,
            path: currentPath,
            isDirectory: isDirectory,
            level: i + 1,
          );
          nodeMap[currentPath] = node;

          debugPrint('FileTree: Node: $currentPath -> dir: $isDirectory, level: ${i + 1}');
        }
      }
    }

    // Build parent-child relationships with improved validation
    for (final path in uniquePaths) {
      final pathParts = path.split('/');

      // For each path, ensure all parent-child relationships are established
      for (int i = 1; i < pathParts.length; i++) {
        final childPath = pathParts.sublist(0, i + 1).join('/');
        final parentPath = pathParts.sublist(0, i).join('/');

        final parent = nodeMap[parentPath];
        final child = nodeMap[childPath];

        if (parent != null && child != null) {
          // Check if child is already added to parent
          if (!parent.children.any((c) => c.path == child.path)) {
            parent.children.add(child);
            debugPrint('FileTree: Added child ${child.name} to parent ${parent.name} (child path: ${child.path})');
          }
        } else {
          if (parent == null) {
            debugPrint('FileTree: Warning - parent not found for path: $parentPath (child: $childPath)');
          }
          if (child == null) {
            debugPrint('FileTree: Warning - child not found for path: $childPath (parent: $parentPath)');
          }
        }
      }
    }

    // Debug: Print all node relationships
    debugPrint('FileTree: Final node relationships:');
    for (final entry in nodeMap.entries) {
      if (entry.value.isDirectory && entry.value.children.isNotEmpty) {
        debugPrint('FileTree: Directory ${entry.key} has ${entry.value.children.length} children: ${entry.value.children.map((c) => c.name).join(', ')}');
      }
    }

    // Sort children with directories first
    for (final node in nodeMap.values) {
      node.children.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
    }

    final rootNodes = nodeMap.values.where((node) => node.level == 1).toList();
    rootNodes.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.compareTo(b.name);
    });

    debugPrint('FileTree: Built ${rootNodes.length} root nodes');
    for (final node in rootNodes.take(10)) {
      debugPrint('FileTree: Root ${node.name} (dir: ${node.isDirectory}, children: ${node.children.length})');
      if (node.name == 'lib' || node.children.isNotEmpty) {
        for (final child in node.children.take(5)) {
          debugPrint('FileTree:   ${node.name}/${child.name} (dir: ${child.isDirectory})');
        }
      }
    }

    // Final validation - ensure we have a reasonable number of nodes for a Flutter project
    if (rootNodes.length < 3) {
      debugPrint('FileTree: Warning - only ${rootNodes.length} root nodes found, this seems low for a Flutter project');
    }

    // Special validation for lib directory
    final libNode = rootNodes.firstWhere((node) => node.name == 'lib', orElse: () => FileTreeNode(name: '', path: '', isDirectory: false));
    if (libNode.name == 'lib') {
      debugPrint('FileTree: Lib directory found with ${libNode.children.length} children');
      if (libNode.children.isEmpty) {
        debugPrint('FileTree: WARNING - lib directory has no children, this is unusual for a Flutter project');
      }
    }

    return rootNodes;
  }

  static List<FileTreeNode> flattenTree(
    List<FileTreeNode> nodes,
    Set<String> expandedPaths,
  ) {
    final List<FileTreeNode> flattened = [];

    void addNodes(List<FileTreeNode> nodeList) {
      for (final node in nodeList) {
        flattened.add(node);
        if (node.isDirectory && expandedPaths.contains(node.path)) {
          addNodes(node.children);
        }
      }
    }

    addNodes(nodes);
    return flattened;
  }
}

// Progressive loading service
class ProgressiveFileTreeService {
  final SshService _sshService;
  final String _projectPath;

  ProgressiveFileTreeService(this._sshService, this._projectPath);

  // Load initial structure (2-3 levels deep)
  Future<List<FileTreeNode>> loadInitialStructure() async {
    debugPrint('FileTree: Loading initial structure (2-3 levels)');
    
    // Load just root + 2 levels deep for immediate UI
    final findCommands = [
      'cd "$_projectPath" 2>/dev/null && timeout 15 find . -maxdepth 3 -not -path "*/\\.*" -not -name ".*" \\( -type f -o -type d \\) 2>/dev/null | head -300 | sort',
      'cd "$_projectPath" 2>/dev/null && find . -maxdepth 3 -not -path "*/\\.*" -not -name ".*" \\( -type f -o -type d \\) 2>/dev/null | head -300 | sort',
      'cd "$_projectPath" 2>/dev/null && find . -maxdepth 2 2>/dev/null | grep -v "/\\." | head -100 | sort',
      'cd "$_projectPath" 2>/dev/null && ls -1AF 2>/dev/null | head -50',
    ];

    String? result;
    for (int i = 0; i < findCommands.length; i++) {
      try {
        result = await _sshService.runCommandLenient(findCommands[i]);
        if (result != null && result.trim().isNotEmpty) {
          final lines = result.split('\n').where((line) => line.trim().isNotEmpty).toList();
          if (lines.length >= 5) {
            debugPrint('FileTree: Initial load successful with ${lines.length} results');
            break;
          }
        }
      } catch (e) {
        debugPrint('FileTree: Initial load command ${i + 1} failed: $e');
      }
    }

    if (result == null || result.trim().isEmpty) {
      throw Exception('Failed to load initial project structure');
    }

    return FileTreeService.parseFileList(result);
  }

  // Load specific directory contents
  Future<List<FileTreeNode>> loadDirectory(String dirPath) async {
    debugPrint('FileTree: Loading directory contents for: $dirPath');
    
    final fullPath = dirPath == '.' ? _projectPath : '$_projectPath/$dirPath';
    
    try {
      // Get directory contents with reasonable depth
      final result = await _sshService.runCommandLenient(
        'cd "$fullPath" 2>/dev/null && find . -maxdepth 2 -not -path "*/\\.*" -not -name ".*" \\( -type f -o -type d \\) 2>/dev/null | head -200 | sort'
      );
      
      if (result == null || result.trim().isEmpty) {
        return [];
      }

      // Parse results and adjust paths to be relative to project root
      final nodes = FileTreeService.parseFileList(result);
      
      // Adjust paths to be relative to project root
      return _adjustPathsForDirectory(nodes, dirPath);
    } catch (e) {
      debugPrint('FileTree: Error loading directory $dirPath: $e');
      return [];
    }
  }

  List<FileTreeNode> _adjustPathsForDirectory(List<FileTreeNode> nodes, String basePath) {
    final adjustedNodes = <FileTreeNode>[];
    
    for (final node in nodes) {
      if (node.path == '.') continue; // Skip the directory itself
      
      final adjustedPath = basePath == '.' ? node.path : '$basePath/${node.path}';
      final adjustedNode = FileTreeNode(
        name: node.name,
        path: adjustedPath,
        isDirectory: node.isDirectory,
        level: node.level + (basePath == '.' ? 0 : basePath.split('/').length),
      );
      
      adjustedNodes.add(adjustedNode);
    }
    
    return adjustedNodes;
  }
}

final progressiveFileTreeServiceProvider = Provider<ProgressiveFileTreeService>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final projectPath = ref.watch(currentProjectPathProvider);
  return ProgressiveFileTreeService(sshService, projectPath);
});

// Updated main file tree provider - now loads only initial structure
final fileTreeProvider = FutureProvider<List<FileTreeNode>>((ref) async {
  final service = ref.watch(progressiveFileTreeServiceProvider);
  final sshService = ref.watch(sshServiceProvider);
  final projectPath = ref.watch(currentProjectPathProvider);

  if (!sshService.isConnected) {
    throw Exception('Not connected to SSH server');
  }

  if (projectPath.isEmpty) {
    return []; // No project selected
  }

  try {
    // Ensure SSH connection is stable before proceeding
    debugPrint('FileTree: Starting initial load for $projectPath');
    
    // Add a loading delay to ensure user sees loading state and SSH is stable
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Verify SSH connection is still stable
    final sshNotifier = ref.read(sshServiceProvider.notifier);
    await sshNotifier.ensureConnected();
    
    // Load initial structure (much simpler and faster)
    final initialNodes = await service.loadInitialStructure();
    
    // TODO: Add background loading later
    return initialNodes;
  } catch (e) {
    debugPrint('FileTree: Error loading - $e');
    throw Exception('Failed to load file tree: $e');
  }
});

// Background loading function
void startBackgroundLoading(WidgetRef ref, List<FileTreeNode> initialNodes) async {
  debugPrint('FileTree: Starting background loading');
  ref.read(backgroundLoadingProvider.notifier).state = true;
  
  final service = ref.read(progressiveFileTreeServiceProvider);
  final directoryStates = ref.read(directoryStatesProvider.notifier);
  
  // Get all directories from initial nodes that need background loading
  final directoriesToLoad = <String>[];
  
  void collectDirectories(List<FileTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isDirectory) {
        directoriesToLoad.add(node.path);
        collectDirectories(node.children);
      }
    }
  }
  
  collectDirectories(initialNodes);
  
  // Load each directory in background
  for (final dirPath in directoriesToLoad) {
    try {
      debugPrint('FileTree: Background loading $dirPath');
      
      // Set loading state
      final currentStates = directoryStates.state;
      directoryStates.state = {
        ...currentStates,
        dirPath: DirectoryState(state: DirectoryLoadingState.loading),
      };
      
      // Load directory contents
      final children = await service.loadDirectory(dirPath);
      
      // Update with loaded state
      directoryStates.state = {
        ...directoryStates.state,
        dirPath: DirectoryState(
          state: DirectoryLoadingState.loaded,
          children: children,
          estimatedCount: children.length,
        ),
      };
      
      debugPrint('FileTree: Background loaded $dirPath with ${children.length} children');
      
      // Small delay between directory loads to not overwhelm the SSH connection
      await Future.delayed(const Duration(milliseconds: 200));
      
    } catch (e) {
      debugPrint('FileTree: Background loading failed for $dirPath: $e');
      
      // Set error state
      directoryStates.state = {
        ...directoryStates.state,
        dirPath: DirectoryState(
          state: DirectoryLoadingState.error,
          error: e.toString(),
        ),
      };
    }
  }
  
  ref.read(backgroundLoadingProvider.notifier).state = false;
  debugPrint('FileTree: Background loading complete');
}

final selectedFileProvider = StateProvider<String?>((ref) => null);
final fileContentProvider = StateProvider<String?>((ref) => null);
final codeControllerProvider = StateProvider<CodeController?>((ref) => null);
final expandedDirectoriesProvider = StateProvider<Set<String>>((ref) => {});
final fileSearchQueryProvider = StateProvider<String>((ref) => '');

// Progressive loading providers
enum DirectoryLoadingState { empty, loading, loaded, error }

class DirectoryState {
  final DirectoryLoadingState state;
  final List<FileTreeNode> children;
  final int estimatedCount;
  final String? error;

  DirectoryState({
    required this.state,
    this.children = const [],
    this.estimatedCount = 0,
    this.error,
  });

  DirectoryState copyWith({
    DirectoryLoadingState? state,
    List<FileTreeNode>? children,
    int? estimatedCount,
    String? error,
  }) {
    return DirectoryState(
      state: state ?? this.state,
      children: children ?? this.children,
      estimatedCount: estimatedCount ?? this.estimatedCount,
      error: error ?? this.error,
    );
  }
}

final directoryStatesProvider = StateProvider<Map<String, DirectoryState>>((ref) => {});
final backgroundLoadingProvider = StateProvider<bool>((ref) => false);

// Filtered file tree provider that filters based on search query
final filteredFileTreeProvider = Provider<AsyncValue<List<FileTreeNode>>>((ref) {
  final fileTreeAsync = ref.watch(fileTreeProvider);
  final searchQuery = ref.watch(fileSearchQueryProvider);
  
  return fileTreeAsync.when(
    data: (nodes) {
      if (searchQuery.trim().isEmpty) {
        return AsyncValue.data(nodes);
      }
      
      // Filter nodes based on search query
      final query = searchQuery.toLowerCase();
      final filteredNodes = <FileTreeNode>[];
      
      void filterNodes(List<FileTreeNode> nodeList, List<FileTreeNode> result) {
        for (final node in nodeList) {
          // Check if current node matches
          final matches = node.name.toLowerCase().contains(query);
          
          // Check if any children match
          final matchingChildren = <FileTreeNode>[];
          filterNodes(node.children, matchingChildren);
          
          // Include node if it matches or has matching children
          if (matches || matchingChildren.isNotEmpty) {
            final filteredNode = node.copyWith(children: matchingChildren);
            result.add(filteredNode);
          }
        }
      }
      
      filterNodes(nodes, filteredNodes);
      return AsyncValue.data(filteredNodes);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// File content provider that loads content when file is selected
final currentFileContentProvider = FutureProvider<String?>((ref) async {
  final selectedFile = ref.watch(selectedFileProvider);
  final fileOpsService = ref.watch(fileOperationsServiceProvider);

  if (selectedFile == null) return null;

  try {
    // Add a loading delay to ensure user sees loading state for files
    await Future.delayed(const Duration(milliseconds: 300));
    
    debugPrint('FileContent: Starting load for $selectedFile');
    final content = await fileOpsService.readFile(selectedFile);
    debugPrint('FileContent: Successfully loaded ${content?.length ?? 0} characters');
    return content;
  } catch (e) {
    debugPrint('FileContent: Error loading - $e');
    throw Exception('Failed to load file: $e');
  }
});

// File Operations Service
class FileOperationsService {
  final SshService _sshService;
  final String _projectPath;

  FileOperationsService(this._sshService, this._projectPath);

  Future<void> createFile(String filePath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }
    await _sshService.runCommand('cd "$_projectPath" && touch "$filePath"');
  }

  Future<void> createDirectory(String dirPath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }
    await _sshService.runCommand('cd "$_projectPath" && mkdir -p "$dirPath"');
  }

  Future<void> deleteFile(String filePath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }
    await _sshService.runCommand('cd "$_projectPath" && rm "$filePath"');
  }

  Future<void> deleteDirectory(String dirPath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }
    await _sshService.runCommand('cd "$_projectPath" && rm -rf "$dirPath"');
  }

  Future<void> renameFile(String oldPath, String newPath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }
    await _sshService.runCommand(
      'cd "$_projectPath" && mv "$oldPath" "$newPath"',
    );
  }

  Future<String?> readFile(String filePath) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }

    // Debug

    try {
      // Handle both relative and absolute paths
      String absolutePath;
      if (filePath.startsWith('/')) {
        // Already absolute path
        absolutePath = filePath;
      } else {
        // Relative path - combine with project path
        absolutePath = '$_projectPath/$filePath';
      }

      // Debug

      // Try using SFTP for more reliable file reading
      try {
        final sftpClient = await _sshService.sftp();
        final file = await sftpClient.open(absolutePath);
        final bytes = <int>[];

        await for (final chunk in file.read()) {
          bytes.addAll(chunk);
        }

        await file.close();
        final content = utf8.decode(bytes);
        // Debug
        return content;
      } catch (sftpError) {
        // Debug

        // Fallback to cat command
        final content = await _sshService.runCommandLenient(
          'cat "$absolutePath"',
        );
        if (content != null && content.isNotEmpty) {
          // Debug
          return content;
        }

        // Check if file exists
        final exists = await _sshService.runCommandLenient(
          'test -f "$absolutePath" && echo "exists"',
        );
        if (exists?.trim() != 'exists') {
          // Debug
          throw Exception('File not found: $filePath');
        }

        // File exists but couldn't read - might be empty
        // Debug
        return '';
      }
    } catch (e) {
      // Debug
      throw Exception('Failed to read file: $e');
    }
  }

  Future<void> writeFile(String filePath, String content) async {
    if (!_sshService.isConnected) {
      throw Exception('Not connected to SSH server');
    }
    if (_projectPath.isEmpty) {
      throw Exception('No project selected');
    }

    // Escape content for shell
    final escapedContent = content
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\$', '\\\$')
        .replaceAll('`', '\\`');

    await _sshService.runCommand(
      'cd "$_projectPath" && echo "$escapedContent" > "$filePath"',
    );
  }
}

final fileOperationsServiceProvider = Provider<FileOperationsService>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final projectPath = ref.watch(currentProjectPathProvider);
  // Debug
  return FileOperationsService(sshService, projectPath);
});

// Utility: Normalize path (replace multiple slashes with one)
String normalizePath(String path) {
  return path.replaceAll(RegExp(r'/+'), '/');
}

class InAppFileBrowser extends ConsumerStatefulWidget {
  final ValueChanged<String> onDirectorySelected;
  final String initialPath;

  const InAppFileBrowser({
    super.key,
    required this.onDirectorySelected,
    this.initialPath = '/',
  });

  @override
  ConsumerState<InAppFileBrowser> createState() => _InAppFileBrowserState();
}

class _InAppFileBrowserState extends ConsumerState<InAppFileBrowser> {
  late String _currentPath;
  late Future<List<FileSystemEntity>> _currentDirectoryContent;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final TextEditingController _pathController = TextEditingController();
  bool _isNavigating = false;
  List<FileSystemEntity>? _lastSuccessfulData;

  @override
  void initState() {
    super.initState();
    _currentPath = normalizePath(widget.initialPath);
    _pathController.text = _currentPath;
    _loadDirectoryContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _loadDirectoryContent() async {
    final sshService = ref.read(sshServiceProvider);
    final sshNotifier = ref.read(sshServiceProvider.notifier);
    
    // Ensure connection is stable
    await sshNotifier.ensureConnected();
    
    final normalizedPath = normalizePath(_currentPath);
    
    // Start loading immediately - the listDirectoryWithRetry method handles validation
    setState(() {
      _currentDirectoryContent = sshService.listDirectoryWithRetry(normalizedPath).then((data) {
        _lastSuccessfulData = data;
        return data;
      });
    });
  }

  void _navigateTo(String path) async {
    final normalizedPath = normalizePath(path);
    
    // Only update state if path actually changed to prevent unnecessary rebuilds
    if (normalizedPath != _currentPath) {
      // Set navigation state to show loading overlay
      setState(() {
        _isNavigating = true;
        _currentPath = normalizedPath;
        _pathController.text = _currentPath;
        _searchQuery = '';
        _searchController.clear();
      });
      
      try {
        // Load new directory content in background
        final sshService = ref.read(sshServiceProvider);
        final sshNotifier = ref.read(sshServiceProvider.notifier);
        await sshNotifier.ensureConnected();
        
        // Add small delay for smooth UX
        await Future.delayed(const Duration(milliseconds: 100));
        
        final newContent = await sshService.listDirectoryWithRetry(normalizedPath);
        
        // Update with new content
        setState(() {
          _currentDirectoryContent = Future.value(newContent);
          _lastSuccessfulData = newContent;
          _isNavigating = false;
        });
      } catch (e) {
        // Handle error while keeping previous content visible
        setState(() {
          _currentDirectoryContent = Future.error(e);
          _isNavigating = false;
        });
      }
    }
  }

  
 
   @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Current path and navigation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: TextField(
              controller: _pathController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter path...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: _currentPath == '/'
                      ? null
                      : () {
                          final parentPath = _currentPath.substring(
                            0,
                            _currentPath.lastIndexOf('/'),
                          );
                          _navigateTo(parentPath.isEmpty ? '/' : parentPath);
                      },
                  splashRadius: 20,
                ),
                                suffixIcon: IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                  onPressed: () {
                    final newPath = normalizePath(_pathController.text.trim());
                    if (newPath.isNotEmpty) {
                      // Navigate to the path in the browser first, then select it
                      // This prevents flickering by showing smooth navigation
                      _navigateTo(newPath);
                      // Small delay then select the final path
                      Future.delayed(const Duration(milliseconds: 100), () {
                        widget.onDirectorySelected(newPath);
                      });
                    }
                  },
                  splashRadius: 20,
                ),
              ),
              onSubmitted: (value) {
                final newPath = normalizePath(value.trim());
                if (newPath.isNotEmpty) {
                  _navigateTo(newPath);
                }
              },
            ),
          ),
        ),
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search in this folder...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
                      tooltip: 'Refresh',
                      onPressed: () {
                        _loadDirectoryContent();
                      },
                      splashRadius: 20,
                    ),
                  ],
                ),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
                // File list
        Expanded(
          child: Stack(
            children: [
              FutureBuilder<List<FileSystemEntity>>(
                future: _currentDirectoryContent,
                builder: (context, snapshot) {
                  // Always maintain black background
                  Widget content;
                  
                  if (snapshot.connectionState == ConnectionState.waiting && _lastSuccessfulData == null) {
                    content = const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError && _lastSuccessfulData == null) {
                    content = Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  } else {
                    // Use current data or fallback to last successful data during navigation
                    final dataToShow = snapshot.hasData ? snapshot.data! : (_lastSuccessfulData ?? <FileSystemEntity>[]);
                    
                    if (dataToShow.isEmpty) {
                      content = const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No files found in this directory',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    } else {
                      final filtered = _searchQuery.isEmpty
                          ? dataToShow
                          : dataToShow
                              .where((entity) => entity.name
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase()))
                              .toList();
                      
                      if (filtered.isEmpty) {
                        content = const Center(
                          child: Text(
                            'No files or folders match your search',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      } else {
                        content = ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entity = filtered[index];
                            return ListTile(
                              leading: Icon(
                                entity.type == FileSystemEntityType.directory
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                                color: Colors.white70,
                              ),
                              title: Text(
                                entity.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                if (entity.type == FileSystemEntityType.directory) {
                                  _navigateTo(entity.path);
                                }
                              },
                            );
                          },
                        );
                      }
                    }
                  }
                  
                  return Container(
                    color: Colors.black,
                    child: content,
                  );
                },
              ),
              // Loading overlay during navigation
              if (_isNavigating)
                Container(
                  color: Colors.black.withValues(alpha:0.7),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Language detection helper
highlight.Mode? _getLanguageMode(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  switch (extension) {
    case 'dart':
      return dart;
    case 'yaml':
    case 'yml':
      return yaml;
    case 'json':
      return json;
    case 'js':
    case 'ts':
      return javascript;
    default:
      return null;
  }
}

// File Explorer Widget
class FileExplorerWidget extends ConsumerWidget {
  const FileExplorerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredNodesAsync = ref.watch(filteredFileTreeProvider);
    final expandedDirectories = ref.watch(expandedDirectoriesProvider);
    final projectPath = ref.watch(currentProjectPathProvider);
    final searchQuery = ref.watch(fileSearchQueryProvider);

    // Show project selection if no project is selected
    if (projectPath.isEmpty) {
      return _buildProjectSelector(context, ref);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header with project path and refresh button
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              right: 8,
              bottom: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    projectPath.split('/').last,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.history, size: 20, color: Colors.white),
                  tooltip: 'Recent Projects',
                  onPressed: () => _showRecentProjectsPopup(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  onPressed: () => _showProjectSelector(context, ref),
                  tooltip: 'Change Project',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20, color: Colors.white),
                  tooltip: 'Refresh',
                  onPressed: () async {
                    debugPrint('FileTree: Manual refresh triggered');
                    
                    // Clear expanded directories for fresh start
                    ref.read(expandedDirectoriesProvider.notifier).state = {};
                    
                    // Ensure connection is stable before refreshing
                    final sshNotifier = ref.read(sshServiceProvider.notifier);
                    await sshNotifier.ensureConnected();
                    
                    // Add small delay then refresh
                    await Future.delayed(const Duration(milliseconds: 200));
                    
                    // Force refresh the file tree provider
                    debugPrint('FileTree: Forcing file tree refresh');
                    // ignore: unused_result
                    ref.refresh(fileTreeProvider);
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'New',
                  onSelected: (value) => _showCreateDialog(context, ref, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'file',
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file, size: 16),
                          SizedBox(width: 8),
                          Text('New File'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'folder',
                      child: Row(
                        children: [
                          Icon(Icons.folder, size: 16),
                          SizedBox(width: 8),
                          Text('New Folder'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextField(
              onChanged: (value) {
                ref.read(fileSearchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                        onPressed: () {
                          ref.read(fileSearchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white, width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          // File tree with enhanced loading state
          Expanded(
            child: filteredNodesAsync.when(
              data: (filteredNodes) {
                if (filteredNodes.isEmpty) {
                  if (searchQuery.isNotEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No files match your search',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  } else {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No files found in this project',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try creating a new file or folder',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }
                }

                final flattenedNodes = FileTreeService.flattenTree(
                  filteredNodes,
                  expandedDirectories,
                );

                return Consumer(
                  builder: (context, ref, child) {
                    final directoryStates = ref.watch(directoryStatesProvider);
                    
                    return ListView.builder(
                      padding: EdgeInsets.zero, // Remove default padding
                      itemCount: flattenedNodes.length,
                      itemBuilder: (context, index) {
                        final node = flattenedNodes[index];
                        final isExpanded = expandedDirectories.contains(node.path);
                        final dirState = directoryStates[node.path];

                        return Container(
                          margin: EdgeInsets.only(left: (node.level - 1) * 16.0),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor: Colors.transparent, // Remove splash effect
                              highlightColor:
                                  Colors.transparent, // Remove highlight effect
                              onTap: () async {
                                if (node.isDirectory) {
                                  final newExpanded = Set<String>.from(
                                    expandedDirectories,
                                  );
                                  if (isExpanded) {
                                    newExpanded.remove(node.path);
                                    debugPrint('FileTree: Collapsed directory ${node.path}');
                                  } else {
                                    newExpanded.add(node.path);
                                    debugPrint('FileTree: Expanded directory ${node.path}');
                                    
                                    // If directory not loaded, trigger load
                                    if (dirState == null || dirState.state == DirectoryLoadingState.empty) {
                                      final service = ref.read(progressiveFileTreeServiceProvider);
                                      final directoryStatesNotifier = ref.read(directoryStatesProvider.notifier);
                                      
                                      // Set loading state
                                      directoryStatesNotifier.state = {
                                        ...directoryStatesNotifier.state,
                                        node.path: DirectoryState(state: DirectoryLoadingState.loading),
                                      };
                                      
                                      try {
                                        final children = await service.loadDirectory(node.path);
                                        directoryStatesNotifier.state = {
                                          ...directoryStatesNotifier.state,
                                          node.path: DirectoryState(
                                            state: DirectoryLoadingState.loaded,
                                            children: children,
                                            estimatedCount: children.length,
                                          ),
                                        };
                                      } catch (e) {
                                        directoryStatesNotifier.state = {
                                          ...directoryStatesNotifier.state,
                                          node.path: DirectoryState(
                                            state: DirectoryLoadingState.error,
                                            error: e.toString(),
                                          ),
                                        };
                                      }
                                    }
                                  }
                                  ref
                                          .read(expandedDirectoriesProvider.notifier)
                                          .state =
                                      newExpanded;
                                } else {
                                  // Add visual feedback before file loads
                                  debugPrint('FileTree: Selecting file ${node.path}');
                                  ref.read(selectedFileProvider.notifier).state =
                                      node.path;
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (node.isDirectory)
                                          GestureDetector(
                                            onTap: () async {
                                              final newExpanded = Set<String>.from(
                                                expandedDirectories,
                                              );
                                              if (isExpanded) {
                                                newExpanded.remove(node.path);
                                                debugPrint('FileTree: Collapsed directory ${node.path} (chevron)');
                                              } else {
                                                newExpanded.add(node.path);
                                                debugPrint('FileTree: Expanded directory ${node.path} (chevron)');
                                                
                                                // Trigger directory load if needed
                                                if (dirState == null || dirState.state == DirectoryLoadingState.empty) {
                                                  final service = ref.read(progressiveFileTreeServiceProvider);
                                                  final directoryStatesNotifier = ref.read(directoryStatesProvider.notifier);
                                                  
                                                  directoryStatesNotifier.state = {
                                                    ...directoryStatesNotifier.state,
                                                    node.path: DirectoryState(state: DirectoryLoadingState.loading),
                                                  };
                                                  
                                                  try {
                                                    final children = await service.loadDirectory(node.path);
                                                    directoryStatesNotifier.state = {
                                                      ...directoryStatesNotifier.state,
                                                      node.path: DirectoryState(
                                                        state: DirectoryLoadingState.loaded,
                                                        children: children,
                                                        estimatedCount: children.length,
                                                      ),
                                                    };
                                                  } catch (e) {
                                                    directoryStatesNotifier.state = {
                                                      ...directoryStatesNotifier.state,
                                                      node.path: DirectoryState(
                                                        state: DirectoryLoadingState.error,
                                                        error: e.toString(),
                                                      ),
                                                    };
                                                  }
                                                }
                                              }
                                              ref
                                                      .read(
                                                        expandedDirectoriesProvider
                                                            .notifier,
                                                      )
                                                      .state =
                                                  newExpanded;
                                            },
                                            child: _buildDirectoryIcon(isExpanded, dirState),
                                          )
                                        else
                                          const SizedBox(width: 16),
                                        Icon(
                                          node.isDirectory
                                              ? (isExpanded
                                                    ? Icons.folder_open
                                                    : Icons.folder)
                                              : Icons.insert_drive_file,
                                          size: 18,
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              node.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (node.isDirectory)
                                            _buildDirectoryStateIndicator(dirState, node.children.length),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 3,
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Loading project files...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This may take a moment',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading files:\n${error.toString()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        debugPrint('Retry button pressed');
                        // Ensure connection is stable before retrying
                        final sshNotifier = ref.read(sshServiceProvider.notifier);
                        await sshNotifier.ensureConnected();
                        
                        // Add delay to ensure stability
                        await Future.delayed(const Duration(milliseconds: 500));
                        // ignore: unused_result
                        ref.refresh(fileTreeProvider);
                      },
                      child: const Text('Retry'),
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

  Widget _buildDirectoryIcon(bool isExpanded, DirectoryState? dirState) {
    if (dirState?.state == DirectoryLoadingState.loading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
        ),
      );
    }
    
    return Icon(
      isExpanded ? Icons.expand_more : Icons.chevron_right,
      size: 16,
      color: Colors.white70,
    );
  }

  Widget _buildDirectoryStateIndicator(DirectoryState? dirState, int fallbackCount) {
    if (dirState == null) {
      // Show count from initial file tree if available
      if (fallbackCount > 0) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$fallbackCount',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
      return SizedBox.shrink();
    }

    switch (dirState.state) {
      case DirectoryLoadingState.loading:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
      case DirectoryLoadingState.loaded:
        // Always show count badge, even if count is 0
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${dirState.estimatedCount}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      case DirectoryLoadingState.error:
        return Icon(Icons.error, size: 12, color: Colors.red);
      case DirectoryLoadingState.empty:
        return SizedBox.shrink();
    }
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String type) {
    final controller = TextEditingController();
    final isFile = type == 'file';
    final selectedFile = ref.read(selectedFileProvider);
    String basePath = '';
    if (selectedFile != null) {
      // If a directory is selected, use it; if a file is selected, use its parent directory
      if (selectedFile.endsWith('/')) {
        basePath = selectedFile;
      } else if (selectedFile.contains('/')) {
        basePath = selectedFile.substring(0, selectedFile.lastIndexOf('/'));
      }
    } else {
      // Default to project root
      basePath = '';
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: isFile ? '(eg. filename.dart)' : 'folder-name',
              filled: true,
              fillColor: Colors.black,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (value) async {
              final name = value.trim();
              if (name.isNotEmpty) {
                try {
                  final service = ref.read(fileOperationsServiceProvider);
                  String fullPath = basePath.isEmpty ? name : '$basePath/$name';
                  if (isFile) {
                    await service.createFile(fullPath);
                  } else {
                                      await service.createDirectory(fullPath);
                }
                await Future.delayed(const Duration(milliseconds: 200));
                // ignore: unused_result
                ref.refresh(fileTreeProvider);
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error: $e',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProjectSelector(BuildContext context, WidgetRef ref) {
    final allRecentProjects = ref.watch(recentProjectsProvider);
    
    // Filter out any local Mac paths that shouldn't be on remote servers
    final recentProjects = allRecentProjects.where((path) => 
      !path.startsWith('/Users/') && 
      !path.startsWith('/Applications/') && 
      !path.contains('Desktop')
    ).toList();
    
    // Update the provider if we filtered out invalid paths
    if (recentProjects.length != allRecentProjects.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(recentProjectsProvider.notifier).state = recentProjects;
      });
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 320,
              child: ElevatedButton.icon(
                onPressed: () => _showProjectSelector(context, ref),
                icon: const Icon(Icons.folder_open, size: 24, color: Colors.white),
                label: const Text(
                  'Open Project Folder',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.black, // Use a black background
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    side: BorderSide(color: Colors.white, width: 1.0, style: BorderStyle.solid,)
                        .copyWith(color: Colors.white.withAlpha(100)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 320,
              child: ElevatedButton.icon(
                onPressed: () => _showRecentProjectsPopup(context, ref),
                icon: const Icon(Icons.history, size: 24, color: Colors.white),
                label: const Text(
                  'Recent Projects',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    side: BorderSide(color: Colors.white, width: 1.0, style: BorderStyle.solid,)
                        .copyWith(color: Colors.white.withAlpha(100)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          if (recentProjects.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Projects',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey[400]),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentProjects.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: Colors.grey[700], height: 1),
                    itemBuilder: (context, index) {
                      final projectPath = recentProjects[index];
                      return ListTile(
                        title: Text(
                          projectPath,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                          tooltip: 'Remove from recent',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: Colors.black,
                                title: const Text(
                                  'Delete recent project?',
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
                                      ref.read(recentProjectsProvider.notifier).state = List.from(recentProjects)..removeAt(index);
                                    },
                                    icon: const Icon(Icons.check, color: Colors.white),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        onTap: () {
                          _selectProject(ref, projectPath);
                          Navigator.pop(
                            context,
                          ); // Close dialog if opened from dialog
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showProjectSelector(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: Colors.transparent,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.98,
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: InAppFileBrowser(
                    initialPath: '/', // Start from root
                    onDirectorySelected: (path) {
                      _selectProject(ref, path);
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRecentProjectsPopup(BuildContext context, WidgetRef ref) {
    final recentProjects = ref.read(recentProjectsProvider);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6), // semi-transparent modal
      builder: (context) => Center(
        child: Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 8),
                  child: Text('Recent Projects', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                if (recentProjects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No recent projects.', style: TextStyle(color: Colors.white70)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: recentProjects.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final projectPath = recentProjects[index];
                        return ListTile(
                          title: Text(
                            projectPath,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                            tooltip: 'Remove from recent',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: Colors.black,
                                  title: const Text(
                                    'Delete recent project?',
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
                                        ref.read(recentProjectsProvider.notifier).state = List.from(recentProjects)..removeAt(index);
                                      },
                                      icon: const Icon(Icons.check, color: Colors.white),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          onTap: () {
                            _selectProject(ref, projectPath);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectProject(WidgetRef ref, String projectPath) async {
    debugPrint('FileTree: Selecting project: $projectPath');
    
    // Ensure SSH connection is stable
    final sshNotifier = ref.read(sshServiceProvider.notifier);
    final isConnected = await sshNotifier.ensureConnected();
    
    if (!isConnected) {
      debugPrint('FileTree: SSH connection not stable, cannot select project');
      return;
    }
    
    // Clear any previous file selection
    ref.read(selectedFileProvider.notifier).state = null;
    
    // Clear expanded directories for fresh start
    ref.read(expandedDirectoriesProvider.notifier).state = {};
    
    // Update current project path
    ref.read(currentProjectPathProvider.notifier).state = projectPath;

    // Add to recent projects
    final recentProjects = ref.read(recentProjectsProvider);
    final updatedRecent = [
      projectPath,
      ...recentProjects.where((p) => p != projectPath),
    ];
    ref.read(recentProjectsProvider.notifier).state = updatedRecent
        .take(10)
        .toList();

    // Wait for state to propagate, then trigger file tree load
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Force refresh the file tree provider to ensure fresh load
    debugPrint('FileTree: Triggering file tree refresh for: $projectPath');
    // ignore: unused_result
    ref.refresh(fileTreeProvider);
    
    debugPrint('FileTree: Project selection complete for: $projectPath');
  }
}

// Code Editor Widget
class CodeEditorWidget extends ConsumerWidget {
  const CodeEditorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFile = ref.watch(selectedFileProvider);
    final fileContentAsync = ref.watch(currentFileContentProvider);

    if (selectedFile == null) {
      return Container(); // Empty container when no file selected
    }

    return fileContentAsync.when(
      data: (content) {
        if (content == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Could not read file',
                  style: TextStyle(fontSize: 18, color: Colors.red),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.read(selectedFileProvider.notifier).state = null,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        // Debug

        final mode = _getLanguageMode(selectedFile);
        final codeController = CodeController(text: content, language: mode);

        return _buildEditor(context, ref, selectedFile, codeController);
      },
      loading: () {
        // Debug
        return const Center(child: CircularProgressIndicator());
      },
      error: (error, stack) {
        // Debug
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading file:\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => ref.read(selectedFileProvider.notifier).state = null,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Back to Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () => ref.refresh(currentFileContentProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor(
    BuildContext context,
    WidgetRef ref,
    String selectedFile,
    CodeController codeController,
  ) {
    return Column(
      children: [
        // Compact file header with status bar padding
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8, // Status bar + padding
            left: 12,
            right: 12,
            bottom: 8,
          ),
          decoration: const BoxDecoration(color: Colors.black),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white,
                ),
                onPressed: () =>
                    ref.read(selectedFileProvider.notifier).state = null,
                tooltip: 'Back to files',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const Icon(
                Icons.insert_drive_file,
                size: 14,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selectedFile.split('/').last,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.save, size: 18, color: Colors.white),
                onPressed: () =>
                    _saveFile(context, ref, selectedFile, codeController),
                tooltip: 'Save',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 18,
                  color: Colors.white,
                ),
                onSelected: (value) =>
                    _handleFileAction(context, ref, value, selectedFile),
                padding: const EdgeInsets.all(4),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Code editor - with orientation-aware key and better layout handling
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CodeTheme(
                data: CodeThemeData(styles: monokaiSublimeTheme),
                child: Container(
                  color: Colors.black,
                  child: SingleChildScrollView(
                    child: CodeField(
                      // Add key that changes with orientation to force rebuild
                      key: Key('${selectedFile}_${MediaQuery.of(context).orientation}_${constraints.maxWidth}'),
                      controller: codeController,
                      background: Colors.black,
                      textStyle: const TextStyle(
                        fontFamily: 'SF Mono',
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white,
                      ),
                      gutterStyle: const GutterStyle(
                        width: 80, // Wider gutter for up to 4-digit line numbers
                        textStyle: TextStyle(
                          fontFamily: 'SF Mono',
                          fontSize: 10, // Small font for line numbers
                          color: Colors.grey,
                        ),
                        background: Colors.black,
                        showLineNumbers: true,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        border: Border(), // Explicitly set empty border
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _saveFile(
    BuildContext context,
    WidgetRef ref,
    String filePath,
    CodeController controller,
  ) async {
    try {
      final service = ref.read(fileOperationsServiceProvider);
      await service.writeFile(filePath, controller.text);
      ref.read(fileContentProvider.notifier).state = controller.text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'File saved successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save file: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleFileAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    String filePath,
  ) {
    switch (action) {
      case 'rename':
        _showRenameDialog(context, ref, filePath);
        break;
      case 'delete':
        _showDeleteDialog(context, ref, filePath);
        break;
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, String filePath) {
    final controller = TextEditingController(text: filePath.split('/').last);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != filePath.split('/').last) {
                try {
                  final service = ref.read(fileOperationsServiceProvider);
                  final directory = filePath.contains('/')
                      ? filePath.substring(0, filePath.lastIndexOf('/'))
                      : '.';
                  final newPath = directory == '.'
                      ? newName
                      : '$directory/$newName';

                  await service.renameFile(filePath, newPath);
                  // ignore: unused_result
                  ref.refresh(fileTreeProvider);
                  ref.read(selectedFileProvider.notifier).state = newPath;
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error: $e',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.black,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${filePath.split('/').last}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final service = ref.read(fileOperationsServiceProvider);
                await service.deleteFile(filePath);
                // ignore: unused_result
                ref.refresh(fileTreeProvider);
                ref.read(selectedFileProvider.notifier).state = null;
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Error: $e',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.black,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// Main Editor Screen
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sshService = ref.watch(sshServiceProvider);

    if (!sshService.isConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Connect to your server to use edit',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer(
        builder: (context, ref, child) {
          final selectedFile = ref.watch(selectedFileProvider);

          final projectPath = ref.watch(currentProjectPathProvider);

          if (selectedFile != null) {
            // File selected - show full screen editor
            return const CodeEditorWidget();
          } else if (projectPath.isNotEmpty) {
            // Project selected but no file - show only file tree
            return const FileExplorerWidget();
          } else {
            // No project selected - show project selector
            return const FileExplorerWidget();
          }
        },
      ),
    );
  }
}
