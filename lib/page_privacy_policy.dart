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
      // Comfortable long-form reading: scrollable, with a constrained measure
      // so lines don't get uncomfortably long on tablets/desktop.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: getPrivacyPolicyChildren(context),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Text(text,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19)),
    );
  }

  Widget _body(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(text,
        style: theme.textTheme.bodyLarge
            ?.copyWith(height: 1.55, color: theme.colorScheme.onSurface));
  }

  List<Widget> getPrivacyPolicyChildren(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sharingEnabled = sharing.isEnabled;
    return [
      Text('Privacy Policy', style: tt.displaySmall?.copyWith(fontSize: 28)),
      const SizedBox(height: 6),
      Text('Last updated 2026-05-27',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      _body(context,
          '$appName ("we", "us", or "our") operates the $appName mobile application (the "App").'),
      _heading(context, 'Information Collection and Use'),
      _body(context,
          'Browsing the dictionary itself does not require an account and does not collect or transmit any personal information about you. We do not use analytics tools or third-party trackers.'),
      if (sharingEnabled) ...[
        const SizedBox(height: 12),
        _body(context,
            'The optional shared-lists feature requires you to sign in with Apple, Google, or Facebook. When you sign in, our server receives a verified user identifier from the provider you chose and the display name they expose (e.g. "Alice Smith"). We store the identifier and display name in our cloud storage so we can show your name on lists you share, recognize you on subsequent sign-ins, and let other members of a shared list see who added what. Lists you create or are invited to — their display name and the dictionary entry keys in them — are stored on our server and shared with the other members of each list. If you generate a public share link for a list, anyone with that link can read it. We do not request or store your email address, contacts, profile photo, or anything else from the sign-in provider.'),
      ],
      _heading(context, 'Data Retention and Deletion'),
      _body(
          context,
          sharingEnabled
              ? 'Lists you have shared remain on our server until you delete them (use "Stop sharing" on the list, or "Clear sharing data" in Settings). When you sign out, your session is removed from this device, but your shared lists stay on the server so you can manage them after signing back in. To request full deletion of your account record (display name + user id), contact us at the address below — we will remove your record and any lists you own.'
              : 'Since we do not collect any user data, we do not retain or delete any personal information.'),
      _heading(context, 'Security'),
      _body(
          context,
          sharingEnabled
              ? 'Sign-in sessions are stored in your device\'s secure keychain (iOS Keychain / Android EncryptedSharedPreferences). Communication with our server uses HTTPS. We verify sign-in credentials against the issuing provider before issuing our own session token. Our server runs on Cloudflare and we do not log request bodies or list contents.'
              : 'We are committed to ensuring that your information is secure. However, since we do not collect any data, there are no security concerns regarding personal data within the App.'),
      _heading(context, 'Changes to This Privacy Policy'),
      _body(context,
          'We may update our Privacy Policy from time to time. Any changes will be posted on this page.'),
      _heading(context, 'Contact Us'),
      _body(context,
          'If you have any questions or suggestions about our Privacy Policy, do not hesitate to contact us at:'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () async {
            final Uri emailUri = Uri(scheme: 'mailto', path: email);
            if (await canLaunchUrl(emailUri)) {
              await launchUrl(emailUri);
            } else {
              throw 'Could not launch $emailUri';
            }
          },
          child: Text(
            email,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    ];
  }
}
