import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage(
      {super.key, required this.appName, required this.email});

  final String appName;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Privacy Policy"),
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
            '2024-10-30',
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
        'The App does not collect, store, or share any personal or sensitive user data. We do not use any analytics tools or third-party services that collect data from your use of the App.',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Data Retention and Deletion',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      const Text(
        'Since we do not collect any user data, we do not retain or delete any personal information.',
        textAlign: TextAlign.left,
      ),
      const SizedBox(height: 20),
      const Text(
        'Security',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      const Text(
        'We are committed to ensuring that your information is secure. However, since we do not collect any data, there are no security concerns regarding personal data within the App.',
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
