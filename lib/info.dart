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
                content: 'Terminal-based vibe coding on your own server. Connect via SSH, use CLI AI tools like Gemini CLI, Qwen CLI, or Claude Code to generate projects, and preview results—all from your phone.',
              ),
              
              const SizedBox(height: 28),
              
              // Getting Started section
              const _InfoSection(
                title: 'Getting Started',
                content: '1. Connect to your SSH server\n2. Use AI CLI tools in terminal to code\n3. Start web server with "srvr" button\n4. Preview web apps live',
              ),
              
              const SizedBox(height: 28),
              
              // Help section
              const _InfoSection(
                title: 'Need Help?',
                content: '• Check SSH credentials and network connection\n• Each terminal tab is a separate shell session\n• Install CLI AI tools on your server for best experience',
              ),
              
              const Spacer(),
              
              // Policy links
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PolicyLink(
                    title: 'Privacy',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/privacy.html'),
                  ),
                  const SizedBox(width: 24),
                  _PolicyLink(
                    title: 'Terms',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/terms.html'),
                  ),
                  const SizedBox(width: 24),
                  _PolicyLink(
                    title: 'Support',
                    onTap: () => _launchURL('https://willbarksdale.github.io/v-policy/support.html'),
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
