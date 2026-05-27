import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'globals.dart';
import 'l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage(
      {super.key, required this.appName, required this.email});

  final String appName;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(DictLibLocalizations.of(context)!.privacyPolicyPageTitle),
        ),
        body: Padding(
            padding:
                const EdgeInsets.only(bottom: 10, left: 20, right: 20, top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: getPrivacyPolicyChildren())));
  }

  List<Widget> getPrivacyPolicyChildren() {
    final sharingEnabled = sharing.isEnabled;
    return [
      const Text(
        'Privacy Policy',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Last updated: '),
          const Text(
            '2026-05-27',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const Text('.'),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        '$appName ("we", "us", or "our") operates the $appName mobile application (the "App").',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Information Collection and Use',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      const Text(
        'Browsing the dictionary itself does not require an account and does not collect or transmit any personal information about you. We do not use analytics tools or third-party trackers.',
        textAlign: TextAlign.left,
      ),
      if (sharingEnabled) ...[
        const SizedBox(height: 10),
        const Text(
          'The optional shared-lists feature requires you to sign in with Apple, Google, or Facebook. When you sign in, our server receives a verified user identifier from the provider you chose and the display name they expose (e.g. "Alice Smith"). We store the identifier and display name in our cloud storage so we can show your name on lists you share, recognize you on subsequent sign-ins, and let other members of a shared list see who added what. Lists you create or are invited to — their display name and the dictionary entry keys in them — are stored on our server and shared with the other members of each list. If you generate a public share link for a list, anyone with that link can read it. We do not request or store your email address, contacts, profile photo, or anything else from the sign-in provider.',
          textAlign: TextAlign.left,
        ),
      ],
      const SizedBox(height: 20),
      const Text(
        'Data Retention and Deletion',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      Text(
        sharingEnabled
            ? 'Lists you have shared remain on our server until you delete them (use "Stop sharing" on the list, or "Clear sharing data" in Settings). When you sign out, your session is removed from this device, but your shared lists stay on the server so you can manage them after signing back in. To request full deletion of your account record (display name + user id), contact us at the address below — we will remove your record and any lists you own.'
            : 'Since we do not collect any user data, we do not retain or delete any personal information.',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Security',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      Text(
        sharingEnabled
            ? 'Sign-in sessions are stored in your device\'s secure keychain (iOS Keychain / Android EncryptedSharedPreferences). Communication with our server uses HTTPS. We verify sign-in credentials against the issuing provider before issuing our own session token. Our server runs on Cloudflare and we do not log request bodies or list contents.'
            : 'We are committed to ensuring that your information is secure. However, since we do not collect any data, there are no security concerns regarding personal data within the App.',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Changes to This Privacy Policy',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      const Text(
        'We may update our Privacy Policy from time to time. Any changes will be posted on this page.',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Contact Us',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'If you have any questions or suggestions about our Privacy Policy, do not hesitate to contact us at ',
          ),
          GestureDetector(
            onTap: () async {
              final Uri emailUri = Uri(
                scheme: 'mailto',
                path: email,
              );
              if (await canLaunchUrl(emailUri)) {
                await launchUrl(emailUri);
              } else {
                throw 'Could not launch $emailUri';
              }
            },
            child: Text(
              email,
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          const Text('.'),
        ],
      ),
    ];
  }
}
