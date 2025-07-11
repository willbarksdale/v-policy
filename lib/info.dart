import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                    // Welcome section
                    _InfoSection(
                    title: 'Welcome to v',
                    content: 'This is a privacy-first, mobile IDE for coding & vibe coding on your own server via SSH.\n\nFeatures:\n• File explorer\n• Code editor\n• Terminal\n• Project management\n• No backend, no tracking.',
                    isLandscape: isLandscape,
                  ),
                    
                    SizedBox(height: isLandscape ? 32 : 48),
                    
                    // Getting Started section
                    _InfoSection(
                    title: 'Getting Started',
                    content: '1. Set up & connect your SSH server\n2. Install AI if you want (Gemini CLI / Claude Code)\n3. Open a project folder and start coding!',
                    isLandscape: isLandscape,
                  ),
                    
                    SizedBox(height: isLandscape ? 32 : 48),
                    
                    // Tips section
                    _InfoSection(
                    title: 'Tips & Shortcuts',
                    content: '• Use the file explorer to browse and edit files\n• Terminal tabs give you multiple shell sessions\n• Use the shortcut bar for common keys & commands\n• Recent projects are saved locally\n• All data stays on your device and server.',
                      isLandscape: isLandscape,
                    ),
                    
                    SizedBox(height: isLandscape ? 32 : 48),
                    
                    // Help section
                    _InfoSection(
                      title: 'Need Help?',
                      content: '• For SSH issues, check your credentials and network\n• Each terminal tab is a separate shell session\n• For more info, view our policy links below',
                      isLandscape: isLandscape,
                    ),
                    
                    // Extra bottom spacing for footer
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            
            // Fixed footer with policy links
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black,
                border: Border(
                  top: BorderSide(color: Colors.white24, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PolicyLink(
                    title: 'Privacy',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/privacy.html'),
                    isLandscape: isLandscape,
                  ),
                  _PolicyLink(
                    title: 'Terms',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/terms.html'),
                    isLandscape: isLandscape,
                  ),
                  _PolicyLink(
                    title: 'Support',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/support.html'),
                    isLandscape: isLandscape,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final String content;
  final bool isLandscape;
  
  const _InfoSection({
    required this.title, 
    required this.content, 
    required this.isLandscape
  });

  @override
  Widget build(BuildContext context) {
    return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isLandscape ? 22 : 26, 
                fontWeight: FontWeight.bold, 
                color: Colors.white
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isLandscape ? 16 : 24),
            Text(
              content,
              style: TextStyle(
                fontSize: isLandscape ? 14 : 16, 
                color: Colors.white70, 
                height: 1.5
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
  final bool isLandscape;

  const _PolicyLink({
    required this.title,
    required this.onTap,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 8 : 12, 
          vertical: isLandscape ? 6 : 8
        ),
        child: Text(
              title,
              style: TextStyle(
            fontSize: isLandscape ? 12 : 14,
            fontWeight: FontWeight.w500,
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