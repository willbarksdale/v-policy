# Contributing to v - Mobile IDE

Thank you for your interest in contributing to **v**! This project aims to create the future of mobile development, and we welcome contributions from developers who share this vision.

## 🌊 The Hyper Wave Philosophy

We're building something that doesn't exist yet—a truly mobile-native development environment. Every contribution, whether it's a bug fix, new feature, or documentation improvement, helps push the boundaries of what's possible in mobile development.

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** (3.8.1 or later)
- **Dart SDK** (included with Flutter)
- **Android Studio** or **VS Code** with Flutter extensions
- **Git** for version control
- **A Linux server with SSH access** for testing (optional but recommended)

### Development Setup

1. **Fork and Clone the Repository**
   ```bash
   git clone https://github.com/willbarksdale/v.git
   cd v
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Verify Setup**
   ```bash
   flutter doctor
   flutter analyze
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

### Setting Up a Test SSH Server

For development and testing, you'll want access to a Linux server:

- **Local**: Use Docker or VirtualBox to run a Linux container/VM
- **Cloud**: Free tiers from Oracle Cloud, AWS, DigitalOcean, or Linode
- **Existing**: Any Linux server you have access to

Basic server requirements:
- SSH daemon running on port 22 (or custom port)
- User account with shell access
- Basic development tools (git, text editors)

## 🛠️ Development Guidelines

### Code Style

- Follow [Dart/Flutter style guide](https://dart.dev/guides/language/effective-dart)
- Use `flutter analyze` to check for issues
- Format code with `dart format .`
- Keep functions focused and well-documented
- Use meaningful variable and function names

### State Management

- We use **Riverpod** for state management
- Create providers in logical groups (SSH, file operations, UI state)
- Use `StateProvider` for simple state, `StateNotifierProvider` for complex state
- Keep business logic separate from UI components

### Architecture Principles

- **Mobile-First**: Every feature should be optimized for touch interfaces
- **Progressive Enhancement**: Fast initial load, then enhance with more features
- **Error Resilience**: Graceful handling of network issues and SSH disconnections
- **Privacy-First**: No data should leave the user's device except via their SSH connection

## 🎯 How to Contribute

### 1. Bug Reports

Found a bug? Please create an issue with:

- **Clear description** of the problem
- **Steps to reproduce** the issue
- **Expected vs. actual behavior**
- **Device info** (iOS/Android version, device model)
- **Server setup** (if relevant to the bug)
- **Screenshots** (if helpful)

### 2. Feature Requests

Have an idea? We'd love to hear it! Please include:

- **Problem statement**: What problem does this solve?
- **Proposed solution**: How should it work?
- **Mobile considerations**: How does it work on touch interfaces?
- **Alternative solutions**: Any other approaches considered?

### 3. Code Contributions

#### Small Changes
- Bug fixes
- UI improvements
- Documentation updates
- Performance optimizations

**Process**: Fork → Create branch → Make changes → Submit PR

#### Large Features
- New screens or major functionality
- Architecture changes
- Integration with external services

**Process**: Create issue → Discuss approach → Fork → Develop → Submit PR

### 4. Pull Request Process

1. **Create a descriptive branch name**
   ```bash
   git checkout -b feature/progressive-git-status
   git checkout -b fix/ssh-reconnection-loop
   git checkout -b docs/setup-instructions
   ```

2. **Make focused commits**
   - One logical change per commit
   - Clear, descriptive commit messages
   - Test your changes thoroughly

3. **Update documentation**
   - Update README if needed
   - Add code comments for complex logic
   - Update this CONTRIBUTING.md if process changes

4. **Test thoroughly**
   - Test on both Android and iOS if possible
   - Test with different SSH server configurations
   - Verify existing functionality still works

5. **Submit PR with**
   - Clear title and description
   - Reference any related issues
   - Screenshots/videos for UI changes
   - Notes about testing performed

## 🧪 Testing

### Manual Testing
- Test SSH connection with various server types
- Verify file operations work correctly
- Check terminal functionality
- Test preview with different web apps
- Try on different screen sizes and orientations

### Automated Testing
- Run `flutter test` before submitting PRs
- Add unit tests for business logic
- Add widget tests for UI components
- Integration tests for critical user flows

## 📋 Priority Areas for Contribution

### High Priority (Phase 2)
- **tmux Integration**: Persistent terminal sessions
- **Advanced File Operations**: Bulk operations, search across files
- **Git UI**: Visual git status, diff viewer, commit interface
- **Improved Terminal**: Better keyboard handling, copy/paste

### Medium Priority (Phase 3)
- **AI Integration**: Code assistance and generation
- **Multiple Preview Tabs**: Side-by-side preview
- **Themes**: Additional color schemes and editor themes
- **Performance**: Memory optimization, faster file loading

### Future Vision (Phase 4+)
- **Local Compilation**: On-device builds for supported languages
- **Collaborative Editing**: Real-time collaboration features
- **Plugin System**: Extensible architecture
- **Advanced Preview**: Device simulation, responsive testing

## 🤝 Community

### Communication
- **GitHub Issues**: Bug reports, feature requests, discussions
- **Pull Requests**: Code contributions and reviews
- **README**: Keep documentation updated

### Code of Conduct

- **Be respectful**: Treat all contributors with respect and kindness
- **Be constructive**: Provide helpful feedback and suggestions
- **Be collaborative**: Work together towards common goals
- **Be patient**: Remember that everyone is learning and growing

### Recognition

All contributors will be acknowledged in the project. Significant contributors may be invited to become maintainers.

## 🌊 Join the Hyper Wave

We're building the future of mobile development. Every contribution, no matter how small, helps push this vision forward. Whether you're fixing a typo, implementing a major feature, or just providing feedback, you're part of creating something revolutionary.

**Let's make traditional computers optional for software development.** 🚀

---

*Questions? Feel free to open an issue for discussion or clarification.* 