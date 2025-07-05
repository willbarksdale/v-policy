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
enum FileSystemEntityType {
  file,
  directory,
}

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
    final lines = findOutput.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final Map<String, FileTreeNode> nodeMap = {};
    
    // print('Parsing ${lines.length} paths'); // Debug
    
    // Remove leading "./" and sort paths
    final cleanPaths = lines
        .map((line) => line.trim())
        .where((path) => path.isNotEmpty && path != '.')
        .map((path) => path.startsWith('./') ? path.substring(2) : path)
        .toSet()
        .toList()
      ..sort();
    
    // print('Clean paths (first 20): ${cleanPaths.take(20).toList()}'); // Debug
    
    // Build all nodes
    for (final path in cleanPaths) {
      final pathParts = path.split('/');
      
      // Build each part of the path
      String currentPath = '';
      for (int i = 0; i < pathParts.length; i++) {
        final part = pathParts[i];
        currentPath = i == 0 ? part : '$currentPath/$part';
        
        if (!nodeMap.containsKey(currentPath)) {
          // Check if this is a directory by seeing if any path starts with this path + "/"
          final isDirectory = cleanPaths.any((p) => p.startsWith('$currentPath/'));
          
          final node = FileTreeNode(
            name: part,
            path: currentPath,
            isDirectory: isDirectory,
            level: i + 1,
          );
          nodeMap[currentPath] = node;
          
          // print('Node: $currentPath -> dir: $isDirectory'); // Debug
        }
      }
    }
    
    // Build parent-child relationships
    for (final path in cleanPaths) {
      final pathParts = path.split('/');
      
      for (int i = 1; i < pathParts.length; i++) {
        final childPath = pathParts.sublist(0, i + 1).join('/');
        final parentPath = pathParts.sublist(0, i).join('/');
        
        final parent = nodeMap[parentPath];
        final child = nodeMap[childPath];
        
        if (parent != null && child != null) {
          if (!parent.children.any((c) => c.path == child.path)) {
            parent.children.add(child);
          }
        }
      }
    }
    
    // Sort children
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
    
    // Debug
    
    return rootNodes;
  }
  
  static List<FileTreeNode> flattenTree(List<FileTreeNode> nodes, Set<String> expandedPaths) {
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

// Providers
final fileTreeProvider = FutureProvider<List<FileTreeNode>>((ref) async {
  final sshService = ref.watch(sshServiceProvider);
  final projectPath = ref.watch(currentProjectPathProvider);
  
  if (!sshService.isConnected) {
    throw Exception('Not connected to SSH server');
  }
  
  if (projectPath.isEmpty) {
    return []; // No project selected
  }
  
  try {
    // Test if directory exists first
    // Debug
    
    // Get everything except hidden files and directories, with depth limit to prevent huge trees
    final result = await sshService.runCommandLenient('cd "$projectPath" && find . -maxdepth 5 -not -path "*/\\.*" -not -name ".*" | head -500 | sort');
    
    if (result == null || result.trim().isEmpty) {
      // Debug
      return [];
    }
    
    // Debug
    
    final nodes = FileTreeService.parseFileList(result);
    // Debug
    return nodes;
  } catch (e) {
    // Debug
    throw Exception('Failed to load file tree: $e');
  }
});

final selectedFileProvider = StateProvider<String?>((ref) => null);
final fileContentProvider = StateProvider<String?>((ref) => null);
final codeControllerProvider = StateProvider<CodeController?>((ref) => null);
final expandedDirectoriesProvider = StateProvider<Set<String>>((ref) => {});

// File content provider that loads content when file is selected
final currentFileContentProvider = FutureProvider<String?>((ref) async {
  final selectedFile = ref.watch(selectedFileProvider);
  final fileOpsService = ref.watch(fileOperationsServiceProvider);
  
  if (selectedFile == null) return null;
  
  try {
    // Debug
    final content = await fileOpsService.readFile(selectedFile);
    // Debug
    return content;
  } catch (e) {
    // Debug
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
    await _sshService.runCommand('cd "$_projectPath" && mv "$oldPath" "$newPath"');
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
        final content = await _sshService.runCommandLenient('cat "$absolutePath"');
        if (content != null && content.isNotEmpty) {
          // Debug
          return content;
        }
        
        // Check if file exists
        final exists = await _sshService.runCommandLenient('test -f "$absolutePath" && echo "exists"');
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
    
    await _sshService.runCommand('cd "$_projectPath" && echo "$escapedContent" > "$filePath"');
  }
}

final fileOperationsServiceProvider = Provider<FileOperationsService>((ref) {
  final sshService = ref.watch(sshServiceProvider);
  final projectPath = ref.watch(currentProjectPathProvider);
  // Debug
  return FileOperationsService(sshService, projectPath);
});

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
    final fileTreeAsync = ref.watch(fileTreeProvider);
    final expandedDirectories = ref.watch(expandedDirectoriesProvider);
    final projectPath = ref.watch(currentProjectPathProvider);

    // Show project selection if no project is selected
    if (projectPath.isEmpty) {
      return _buildProjectSelector(context, ref);
    }

    return Column(
      children: [
        // Header with project path and refresh button
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4, // Status bar + minimal padding
            left: 8,
            right: 8,
            bottom: 4, // Reduced bottom padding
          ),
          decoration: const BoxDecoration(
            color: Colors.black,
            border: Border(bottom: BorderSide(color: Colors.grey)),
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
                icon: const Icon(Icons.folder_open, size: 20),
                onPressed: () => _showProjectSelector(context, ref),
                tooltip: 'Change Project',
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
        // File tree
        Expanded(
          child: fileTreeAsync.when(
            data: (nodes) {
              if (nodes.isEmpty) {
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
              
              final flattenedNodes = FileTreeService.flattenTree(nodes, expandedDirectories);
              
              return ListView.builder(
                padding: EdgeInsets.zero, // Remove default padding
                itemCount: flattenedNodes.length,
                itemBuilder: (context, index) {
                  final node = flattenedNodes[index];
                  final isExpanded = expandedDirectories.contains(node.path);
                  
                  return Container(
                    margin: EdgeInsets.only(left: (node.level - 1) * 16.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        splashColor: Colors.transparent, // Remove splash effect
                        highlightColor: Colors.transparent, // Remove highlight effect
                        onTap: () {
                          if (node.isDirectory) {
                            final newExpanded = Set<String>.from(expandedDirectories);
                            if (isExpanded) {
                              newExpanded.remove(node.path);
                            } else {
                              newExpanded.add(node.path);
                            }
                            ref.read(expandedDirectoriesProvider.notifier).state = newExpanded;
                          } else {
                            ref.read(selectedFileProvider.notifier).state = node.path;
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          child: Row(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (node.isDirectory)
                                    GestureDetector(
                                      onTap: () {
                                        final newExpanded = Set<String>.from(expandedDirectories);
                                        if (isExpanded) {
                                          newExpanded.remove(node.path);
                                        } else {
                                          newExpanded.add(node.path);
                                        }
                                        ref.read(expandedDirectoriesProvider.notifier).state = newExpanded;
                                      },
                                      child: Icon(
                                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 16),
                                  Icon(
                                    node.isDirectory 
                                        ? (isExpanded ? Icons.folder_open : Icons.folder)
                                        : Icons.insert_drive_file,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  node.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
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
            loading: () => const Center(child: CircularProgressIndicator()),
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
                    onPressed: () => ref.refresh(fileTreeProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String type) {
    final controller = TextEditingController();
    final isFile = type == 'file';
    
    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Remove background overlay
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, // Remove dialog background
        elevation: 0, // Remove shadow
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: isFile ? '(eg. filename.dart)' : 'folder-name',
              filled: true,
              fillColor: Colors.black,
              border: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (value) async {
              final name = value.trim();
              if (name.isNotEmpty) {
                try {
                  final service = ref.read(fileOperationsServiceProvider);
                  if (isFile) {
                    await service.createFile(name);
                  } else {
                    await service.createDirectory(name);
                  }
                  // ignore: unused_result
                  ref.refresh(fileTreeProvider);
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
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
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showProjectSelector(context, ref),
              icon: const Icon(Icons.folder),
              label: const Text('Open'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide.none, // Remove button outline
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProjectSelector(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    String? errorMessage;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Project Path on Remote Server',
                  hintText: '/Users/username/my-project',
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => _tryOpenNativeFileBrowser(context, ref, controller, setState),
                    tooltip: 'Try to open native file browser',
                  ),
                  errorText: errorMessage,
                  helperText: 'Enter path or click folder icon to browse',
                ),
                autofocus: true,
                onChanged: (value) {
                  if (errorMessage != null) {
                    setState(() => errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This should be the path to your project folder on the SSH server',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ],
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
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isEmpty) {
                  setState(() => errorMessage = 'Please enter a path');
                  return;
                }
                
                if (!path.startsWith('/')) {
                  setState(() => errorMessage = 'Please enter an absolute path starting with /');
                  return;
                }
                
                // Just proceed with the path - validation will happen when loading files
                _selectProject(ref, path);
                Navigator.pop(context);
              },
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }





  Future<void> _tryOpenNativeFileBrowser(BuildContext context, WidgetRef ref, TextEditingController controller, StateSetter setState) async {
    try {
      final sshService = ref.read(sshServiceProvider);
      if (!sshService.isConnected) {
        setState(() => controller.text = 'SSH not connected');
        return;
      }

      // Show loading message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attempting to open file browser...', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Get current working directory first
      final pwdResult = await sshService.runCommand('pwd');
      final currentDir = pwdResult?.trim() ?? '/';
      
      // Try to detect the OS and open appropriate file manager
      final osResult = await sshService.runCommand('uname -s 2>/dev/null || echo "unknown"');
      final os = osResult?.trim().toLowerCase() ?? 'unknown';
      
      String openCommand;
      if (os.contains('darwin')) {
        // macOS
        openCommand = 'open "$currentDir" &';
      } else if (os.contains('linux')) {
        // Linux - try common file managers
        openCommand = 'xdg-open "$currentDir" 2>/dev/null || nautilus "$currentDir" 2>/dev/null || dolphin "$currentDir" 2>/dev/null || thunar "$currentDir" 2>/dev/null &';
      } else {
        // Unknown OS, try generic
        openCommand = 'xdg-open "$currentDir" 2>/dev/null || open "$currentDir" 2>/dev/null &';
      }
      
      // Attempt to open file manager
      await sshService.runCommand(openCommand);
      
      // Set the current directory in the text field
      controller.text = currentDir;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File browser opened at: $currentDir\nSelect your project folder and enter the path above.'),
          duration: const Duration(seconds: 4),
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open file browser: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _selectProject(WidgetRef ref, String projectPath) {
    // Update current project path
    ref.read(currentProjectPathProvider.notifier).state = projectPath;
    
    // Add to recent projects
    final recentProjects = ref.read(recentProjectsProvider);
    final updatedRecent = [projectPath, ...recentProjects.where((p) => p != projectPath)];
    ref.read(recentProjectsProvider.notifier).state = updatedRecent.take(10).toList();
    
    // Refresh file tree
    // ignore: unused_result
    ref.refresh(fileTreeProvider);
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Could not read file',
                  style: TextStyle(fontSize: 18, color: Colors.red),
                ),
              ],
            ),
          );
        }

        // Debug
        
        final mode = _getLanguageMode(selectedFile);
        final codeController = CodeController(
          text: content,
          language: mode,
        );

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
              ElevatedButton(
                onPressed: () => ref.refresh(currentFileContentProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor(BuildContext context, WidgetRef ref, String selectedFile, CodeController codeController) {
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
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
          child: Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
                onPressed: () => ref.read(selectedFileProvider.notifier).state = null,
                tooltip: 'Back to files',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const Icon(Icons.insert_drive_file, size: 14, color: Colors.white70),
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
                onPressed: () => _saveFile(context, ref, selectedFile, codeController),
                tooltip: 'Save',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                onSelected: (value) => _handleFileAction(context, ref, value, selectedFile),
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
        // Code editor - scrollable with better gutter
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: monokaiSublimeTheme),
            child: Container(
              color: Colors.black,
              child: SingleChildScrollView(
                child: CodeField(
                  controller: codeController,
                  background: Colors.black,
                  textStyle: const TextStyle(
                    fontFamily: 'SF Mono',
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white,
                  ),
                  gutterStyle: const GutterStyle(
                    width: 60, // Increased width to prevent wrapping
                    textStyle: TextStyle(
                      fontFamily: 'SF Mono',
                      fontSize: 10, // Even smaller font for line numbers
                      color: Colors.grey,
                    ),
                    background: Colors.black,
                    showLineNumbers: true,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    border: Border(), // Explicitly set empty border
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }



  Future<void> _saveFile(BuildContext context, WidgetRef ref, String filePath, CodeController controller) async {
    try {
      final service = ref.read(fileOperationsServiceProvider);
      await service.writeFile(filePath, controller.text);
      ref.read(fileContentProvider.notifier).state = controller.text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File saved successfully', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleFileAction(BuildContext context, WidgetRef ref, String action, String filePath) {
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
          decoration: const InputDecoration(
            labelText: 'New name',
          ),
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
                  final newPath = directory == '.' ? newName : '$directory/$newName';
                  
                  await service.renameFile(filePath, newPath);
                  // ignore: unused_result
                  ref.refresh(fileTreeProvider);
                  ref.read(selectedFileProvider.notifier).state = newPath;
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
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
        content: Text('Are you sure you want to delete "${filePath.split('/').last}"?'),
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
                    content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
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