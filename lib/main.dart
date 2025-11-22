import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ssh.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'v',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white,
          surface: Colors.black,
          onSurface: Colors.white,
          error: Colors.red,
          onError: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white),
          displayLarge: TextStyle(color: Colors.white),
          displayMedium: TextStyle(color: Colors.white),
          displaySmall: TextStyle(color: Colors.white),
          headlineLarge: TextStyle(color: Colors.white),
          headlineMedium: TextStyle(color: Colors.white),
          headlineSmall: TextStyle(color: Colors.white),
          titleLarge: TextStyle(color: Colors.white),
          titleMedium: TextStyle(color: Colors.white),
          titleSmall: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
          labelMedium: TextStyle(color: Colors.white),
          labelSmall: TextStyle(color: Colors.white),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: Colors.white30, // A lighter white for selection
          selectionHandleColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          enableFeedback: false, // Disable haptic feedback
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white),
          hintStyle: TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white, // Text color
            backgroundColor: Colors.transparent, // Button background color
            side: const BorderSide(color: Colors.white), // White outline
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================================
// INFO SCREEN
// ============================================================================

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0a0a0a),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Welcome section
              const _InfoSection(
                title: 'Welcome',
                content: 'Terminal-based vibe coding on your own server. Optimized for web development. Connect via SSH, use CLI AI tools like Gemini CLI, Qwen CLI, or Claude Code to generate projects, and preview results—all from your phone or tablet.',
              ),
              
              const SizedBox(height: 28),
              
              // Getting Started section
              const _InfoSection(
                title: 'Getting Started',
                content: '1. Connect to your SSH server\n2. Use AI CLI tools in terminal to code\n3. Start web server in terminal\n4. Preview websites or web apps live',
              ),
              
              const SizedBox(height: 28),
              
              // Help section
              const _InfoSection(
                title: 'Need Help?',
                content: '1. Check SSH credentials & network connection\n2. Each terminal tab is a separate shell session\n3. Install tmux & CLI AI tools on your server for best experience',
              ),
              
              const Spacer(),
              
              // Policy links
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PolicyLink(
                    title: 'Privacy',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v/privacy.html'),
                  ),
                  const SizedBox(width: 24),
                  _PolicyLink(
                    title: 'Terms',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v/terms.html'),
                  ),
                  const SizedBox(width: 24),
                  _PolicyLink(
                    title: 'Support',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v/support.html'),
                  ),
                ],
              ),
              
              // Bottom spacing for nav menu
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final String content;
  
  const _InfoSection({
    required this.title, 
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22, 
            fontWeight: FontWeight.bold, 
            color: Colors.white
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        Text(
          content,
          style: const TextStyle(
            fontSize: 15, 
            fontWeight: FontWeight.w700,
            color: Colors.white70, 
            height: 1.4
          ),
          textAlign: TextAlign.left,
        ),
      ],
    );
  }
}

class _PolicyLink extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _PolicyLink({
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12, 
          vertical: 8
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
