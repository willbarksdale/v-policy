# v – Mobile IDE (BYOS, SSH, tmux, AI-Ready)

## 🧠 Mission Statement

**Create the future. Code anywhere.**

This is a revolutionary, privacy-first, mobile IDE built in Flutter. It transforms your phone into a complete development environment—no desktop, no IDE, no computer needed. Connect to your own server (BYOS), code, run, and preview projects, all from a single, elegant mobile interface.

---

## 🌊 The Hyper Wave Vision

We're building toward a future where **development is truly mobile-native**:

- **Zero Desktop Dependency**: Your phone is your dev machine
- **Fully Local Workflow**: Own your server, own your code
- **AI-Powered Development**: (Planned) Integrated AI assistance for code generation and problem-solving
- **Real-Time Everything**: Live preview, instant feedback, seamless iteration
- **Mobile-First UX**: Designed for touch, optimized for flow, built for creators on the go

The ultimate goal: **Make traditional computers optional for software development.**

---

## ✅ Current Features

### 🔐 Secure SSH Connection
- Elegant login screen with credential storage
- Password visibility toggle and secure key management
- Auto-reconnection and session management
- Persistent SSH session using `dartssh2`
- Keep-alive pings and exponential backoff reconnect

### 💻 Multi-Terminal Environment (tmux-powered)
- Multiple terminal tabs (up to 5 simultaneous sessions)
- Each tab attaches to a persistent tmux session (`v_ide`) on your server
- If you disconnect/reconnect, your shell and running processes are preserved
- Custom keyboard shortcuts: esc, ctrl, arrows, |, >, <, ~, /, \, tab, etc.
- Git and server command popups for fast workflow
- Copy/paste with clipboard integration

### 📝 Advanced Code Editor
- Syntax highlighting for multiple languages
- File explorer UI built from parsed `find` or `ls -R` output via SSH
- Browse directories, open/edit files, save via SFTP
- Auto-save and real-time file sync
- Search and filter files

### 🌐 Live Preview System
- Run a local dev server (e.g. `flutter run -d web-server`)
- Preview your running project in-app via WebView
- Enter a port or custom URL for preview
- Common dev server shortcuts (Flutter, Node.js, Python, etc.)

### 🎨 Polished Mobile UX
- Dark theme, touch-optimized controls, responsive design
- Floating notifications, professional typography, and spacing
- Onboarding/info screen with privacy, terms, and support links

---

## 🛠️ Technical Architecture & Details

### SSH Stability Enhancements
- Server should have in `/etc/ssh/sshd_config`:
  - `ClientAliveInterval 30`
  - `ClientAliveCountMax 10`
- Client sends keep-alive pings (`echo "ping"`) every 60 seconds
- Automatic reconnect attempts when session drops
- Local cache stores session state (open file, terminal tabs, etc.)

### Live Terminal Sessions (tmux Integration)
- The app uses tmux to keep your terminal session alive, even if your network drops or you switch between WiFi and cellular
- When you open a terminal tab, the app creates (or attaches to) a tmux session named `v_ide` on your server
- You can use tmux directly on your server to see these sessions as well
- No extra setup is needed—tmux is installed by default on most Linux servers

### Persistent State
- Stores SSH login credentials and session preferences with shared_preferences
- Restores project path and open files on reconnect

---

## 🏗️ Getting Started

1. **Set up your server** (any Linux VPS with SSH access)
2. **Install development tools** (Node.js, Python, Flutter, etc.)
3. **(Optional) Install Gemini CLI for AI features:**
   ```bash
   sudo apt update
   sudo apt install git curl unzip
   curl -O https://dl.google.com/genai/gemini-cli.zip
   unzip gemini-cli.zip
   sudo mv gemini /usr/local/bin/
   gemini auth login
   ```
4. **Download the app** and connect to your server
5. **Start coding** with full terminal and editor access
6. **Preview live** with built-in WebView rendering

---

## 💡 Development Philosophy

- **BYOS (Bring Your Own Server):** Complete ownership of compute, files, and infrastructure
- **100% Free-Tier Friendly:** Works with Oracle Cloud, AWS Free Tier, DigitalOcean, etc.
- **No Vendor Lock-In:** Pure SSH connection, works with any Linux server
- **Mobile-Native Design:** Built for phones first, not adapted from desktop
- **Privacy-First:** Your code never touches third-party servers
- **Open Source:** Transparent, collaborative, community-driven

---

## 🛣️ Roadmap & Future Vision

### **Phase 1: Foundation** ✅ *Complete*
- SSH connection and multi-terminal support
- Code editor with syntax highlighting
- Live preview and server management
- Core mobile UX patterns

### **Phase 1.5: SSH/tmux Architecture** ✅ *Complete*
- Persistent tmux sessions for all terminals
- Auto-reconnect and session restore
- Local state caching

### **Phase 2: AI Integration** 🚧 *DIY/Planned*
- Integrated AI code assistance (Gemini CLI, Claude, etc.)
- Smart code completion and suggestions
- Automated debugging and optimization
- Natural language to code generation

### **Phase 3: Local Runtime** 🔮 *Future*
- On-device compilation for supported languages
- Local Flutter/React Native builds
- Offline development capabilities
- Edge computing integration

### **Phase 4: Hyper Wave** 🌊 *Vision*
- **Zero-computer development:** Phone-only workflow
- **AI pair programming:** Advanced code generation and review
- **Cloud-edge hybrid:** Seamless local/remote compute switching
- **Mobile dev marketplace:** Share and discover mobile-first tools

---

## 🤝 Contributing

This project represents the future of mobile development. We're building something that doesn't exist yet—a truly mobile-native development environment.

**Join the hyper wave:**
- 🐛 Report bugs and suggest features
- 💻 Contribute code and improvements
- 📖 Improve documentation and guides
- 🌟 Share your mobile development stories

---

## 📄 License

Open source, community-driven. Details in LICENSE file.

---

**The future of development is mobile. The future is now.** 🚀

