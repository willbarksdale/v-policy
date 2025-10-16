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
      color: const Color(0xFF121212),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Welcome section
              _InfoSection(
                title: 'Welcome',
                content: 'Terminal-based vibe coding on your own server. Connect via SSH, use CLI AI tools like Gemini CLI, Qwen CLI, or Claude Code to generate projects, and preview results—all from your phone.',
                isLandscape: isLandscape,
              ),
              
              SizedBox(height: isLandscape ? 20 : 28),
              
              // Getting Started section
              _InfoSection(
                title: 'Getting Started',
                content: '1. Connect to your SSH server\n2. Use AI CLI tools in terminal to generate code\n3. Preview your projects live\n4. Vibe code anywhere',
                isLandscape: isLandscape,
              ),
              
              SizedBox(height: isLandscape ? 20 : 28),
              
              // Help section
              _InfoSection(
                title: 'Need Help?',
                content: '• Check SSH credentials and network connection\n• Each terminal tab is a separate shell session\n• Install CLI AI tools on your server for best experience',
                isLandscape: isLandscape,
              ),
              
              const Spacer(),
              
              // Policy links
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PolicyLink(
                    title: 'Privacy',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/privacy.html'),
                    isLandscape: isLandscape,
                  ),
                  SizedBox(width: isLandscape ? 16 : 24),
                  _PolicyLink(
                    title: 'Terms',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/terms.html'),
                    isLandscape: isLandscape,
                  ),
                  SizedBox(width: isLandscape ? 16 : 24),
                  _PolicyLink(
                    title: 'Support',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/support.html'),
                    isLandscape: isLandscape,
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
            fontSize: isLandscape ? 20 : 22, 
            fontWeight: FontWeight.bold, 
            color: Colors.white
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isLandscape ? 10 : 14),
        Text(
          content,
          style: TextStyle(
            fontSize: isLandscape ? 13 : 15, 
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
