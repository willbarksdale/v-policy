# v – Mobile IDE (BYOS, SSH, Progressive)

## 🧠 Mission Statement

**Create the future. Code anywhere.**

This is a revolutionary, privacy-first, mobile IDE built in Flutter. It transforms your phone into a complete development environment—no desktop, no IDE, no computer needed. Connect to your own server (BYOS), code, run, and preview projects, all from a single, elegant mobile interface.

---

## ✅ Current Features (MVP)

### 🔐 Secure SSH Connection
- Clean SSH login screen with server, port, username, and password fields
- Password visibility toggle and form validation
- Private key authentication support (password and key-based)
- Auto-reconnection with connection status management
- Secure credential storage using `flutter_secure_storage`
- Info screen with privacy policy, terms, and support links

### 📝 Advanced File Management & Code Editor
- **Progressive File Tree Loading**: Smart lazy loading system with loading indicators
- **Project Browser**: Navigate and select project directories via SSH
- **File Explorer**: Browse directories with search/filter capabilities
- **Syntax Highlighting**: Multi-language support (Dart, YAML, JSON, JavaScript)
- **File Operations**: Create, edit, rename, delete files and folders
- **Recent Projects**: Local storage of recently accessed projects
- **Count Badges**: Visual indicators showing file/folder counts
- **SFTP Integration**: Reliable file reading/writing via SSH file transfer

### 💻 Multi-Terminal Environment
- **Multiple Terminal Tabs**: Up to 5 simultaneous terminal sessions
- **Enhanced Terminal UI**: Dark theme with proper rendering
- **Custom Keyboard Bar**: Quick access to special keys (esc, ctrl, arrows, symbols)
- **Command Shortcuts**: Built-in popups for Git, Flutter, and server commands
- **Copy/Paste**: Clipboard integration for terminal operations
- **Session Management**: Terminal tabs with rename and close functionality

### 🌐 Live Preview System
- **WebView Integration**: Built-in browser for previewing web applications
- **Port Configuration**: Connect to dev servers running on your SSH server
- **Custom URL Support**: Enter specific URLs for preview
- **Common Dev Server Shortcuts**: Quick buttons for Flutter web, Node.js, etc.
- **Live Reload**: Real-time preview of running applications

### 🎨 Mobile-Optimized UX
- **Dark Theme**: Professional black theme optimized for coding
- **Touch-Friendly Interface**: Large buttons and touch targets
- **Responsive Design**: Works in both portrait and landscape orientations
- **Navigation Tabs**: Clean bottom navigation between SSH, Edit, Terminal, Preview
- **Loading States**: Visual feedback during file operations and connections
- **Error Handling**: User-friendly error messages and retry mechanisms

---

## 🛠️ Technical Architecture

### Core Technologies
- **Flutter**: Cross-platform mobile framework
- **SSH/SFTP**: `dartssh2` for secure server connections
- **State Management**: `flutter_riverpod` for reactive state
- **File Operations**: Direct SSH command execution and SFTP file transfer
- **Terminal**: `xterm` package for terminal emulation
- **Code Editing**: `flutter_code_editor` with syntax highlighting
- **Web Preview**: `webview_flutter` for in-app browsing

### Progressive Loading System
- **Initial Fast Load**: 2-3 directory levels, up to 300 files for immediate UI response
- **On-Demand Loading**: Directory contents loaded when expanded
- **Loading States**: Visual indicators (spinners, count badges) during operations
- **Error Recovery**: Graceful handling of failed directory loads
- **Smart Caching**: Efficient memory usage for large project structures

### SSH Architecture
- **Connection Stability**: Auto-reconnect with exponential backoff
- **Session Persistence**: Maintains connection state across app lifecycle
- **Command Execution**: Reliable SSH command running with timeout handling
- **Keep-Alive**: Regular pings to maintain connection stability

---

## 🏗️ Getting Started

1. **Set up your server** (any Linux VPS with SSH access)
2. **Install development tools** (Node.js, Python, Flutter, etc.)
3. **Download the app** and connect via SSH credentials
4. **Browse and select** a project directory 
5. **Start coding** with file explorer and editor
6. **Use terminal** for commands, git operations, and running apps
7. **Preview live** with built-in WebView for web applications

---

## 💡 Development Philosophy

- **BYOS (Bring Your Own Server):** Complete ownership of compute, files, and infrastructure
- **100% Free-Tier Friendly:** Works with Oracle Cloud, AWS Free Tier, DigitalOcean, etc.
- **No Vendor Lock-In:** Pure SSH connection, works with any Linux server
- **Mobile-Native Design:** Built for phones first, not adapted from desktop
- **Privacy-First:** Your code never touches third-party servers
- **Progressive Enhancement:** Fast initial load, smart background loading
- **Open Source:** Transparent, collaborative, community-driven

---

## 🛣️ Roadmap & Future Vision

### **Phase 1: Foundation** ✅ *Complete*
- ✅ SSH connection and authentication
- ✅ Multi-terminal support with tabs
- ✅ Progressive file tree loading
- ✅ Code editor with syntax highlighting
- ✅ Live preview and WebView integration
- ✅ Mobile-optimized UX and navigation

### **Phase 2: Enhanced Development Experience** 🚧 *In Progress*
- **tmux Integration**: Persistent terminal sessions that survive disconnections
- **Advanced File Operations**: Bulk operations, file search across projects
- **Git Integration**: Visual git status, diff viewer, commit interface
- **Improved Preview**: Auto-reload, multiple preview tabs, device simulation
- **Keyboard Shortcuts**: Customizable shortcuts and key bindings
- **Themes**: Multiple color schemes and editor themes

### **Phase 3: AI Integration** 🔮 *Planned*
- **AI Code Assistance**: Integration with Gemini CLI, Claude, or similar
- **Smart Code Completion**: Context-aware suggestions and auto-completion  
- **Code Generation**: Natural language to code conversion
- **Automated Debugging**: AI-powered error detection and fixes
- **Documentation Generation**: Auto-generate comments and docs

### **Phase 4: Advanced Features** 🌊 *Future Vision*
- **Local Runtime**: On-device compilation for supported languages
- **Offline Development**: Work without internet connection
- **Team Collaboration**: Real-time collaborative editing
- **Plugin System**: Extensible architecture for custom tools
- **Cloud-Edge Hybrid**: Seamless local/remote compute switching
- **Mobile Dev Marketplace**: Share and discover mobile-first dev tools

### **Phase 5: Hyper Wave** 🚀 *Long-term Vision*
- **Zero-Computer Development**: Phone-only workflow for full-stack development
- **AI Pair Programming**: Advanced code generation, review, and mentoring
- **Augmented Reality**: AR code visualization and 3D project exploration
- **Neural Interface**: Direct thought-to-code translation (research phase)

---

## 🔧 Current Limitations & Known Issues

- **No tmux Integration**: Terminal sessions don't persist across disconnections (planned for Phase 2)
- **Basic Git Support**: Only command-line git operations (visual git interface planned)
- **Limited File Search**: No cross-project search functionality yet
- **Single Preview Tab**: Only one WebView preview at a time
- **iOS Archive Size**: Large build artifacts (now properly excluded from git)

---

## 🤝 Contributing

This project represents the future of mobile development. We're building something that doesn't exist yet—a truly mobile-native development environment that's actually usable for real work.

**Join the hyper wave:**
- 🐛 Report bugs and suggest features via GitHub Issues
- 💻 Contribute code improvements and new features
- 📖 Improve documentation and setup guides
- 🌟 Share your mobile development stories and use cases
- 🧪 Test the app with different server configurations

**Development Setup:**
1. Clone the repository
2. Run `flutter pub get` to install dependencies  
3. Set up a test SSH server for development
4. Run `flutter run` to start the app

---

## 📄 License

Open source, community-driven. See LICENSE file for details.

---

**The future of development is mobile. The MVP is here. Let's build the rest together.** 🚀

