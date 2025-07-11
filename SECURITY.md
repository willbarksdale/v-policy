# Security Policy

## Supported Versions

We actively support the latest version of **v - Mobile IDE**. Security updates will be provided for:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | ✅ Yes             |
| < 1.0   | ❌ No              |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please follow responsible disclosure:

### 🔒 For Security Issues

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead, please:

1. **Email**: Send details to security@[your-domain] (or create a private vulnerability report on GitHub)
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)

### 📧 Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 24-48 hours
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release cycle

### 🛡️ Security Considerations

**v - Mobile IDE** is designed with privacy and security in mind:

- **No Backend**: All data stays on your device and your SSH server
- **Direct SSH**: No intermediary servers or proxies
- **Local Storage**: Credentials stored securely using Flutter Secure Storage
- **BYOS**: You control your server and data

### 🔍 Common Security Areas

When testing, please focus on:

- SSH credential handling and storage
- File upload/download security
- Terminal command injection prevention
- Local data encryption
- Network communication security

### 🏆 Recognition

Security researchers who responsibly disclose vulnerabilities will be:

- Credited in release notes (with permission)
- Listed in our security acknowledgments
- Invited to test future security improvements

## General Security Tips

For users of **v - Mobile IDE**:

1. **Use strong SSH credentials** and consider key-based authentication
2. **Keep your server updated** with latest security patches
3. **Use secure networks** when possible (VPN recommended on public WiFi)
4. **Regular backups** of your projects and server data
5. **Monitor server logs** for any suspicious activity

---

Thank you for helping keep **v** and our community safe! 🔒 