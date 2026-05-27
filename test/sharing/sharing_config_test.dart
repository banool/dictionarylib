import 'package:dictionarylib/sharing/sharing_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const auth = SharingAuthConfig(
    appleBundleId: 'com.example.test',
    googleServerClientId: 'test.google.client.id',
    facebookAppId: 'test-fb-app-id',
  );

  const config = SharingConfig(
    appId: 'auslan',
    appName: 'Auslan Dictionary',
    apiBaseUrl: 'https://share.auslandictionary.com',
    shareLinkBaseUrl: 'https://share.auslandictionary.com/l',
    shareLinkHost: 'share.auslandictionary.com',
    urlScheme: 'auslan',
    auth: auth,
  );

  test('shareUrlFor composes the public URL', () {
    expect(config.shareUrlFor('greetings-101'),
        'https://share.auslandictionary.com/l/greetings-101');
  });

  test('shareUrlFor does not add slashes when base lacks one', () {
    const c = SharingConfig(
      appId: 'a',
      appName: 'A',
      apiBaseUrl: 'https://x.test',
      shareLinkBaseUrl: 'https://x.test/l', // no trailing slash
      shareLinkHost: 'x.test',
      urlScheme: 'a',
      auth: auth,
    );
    expect(c.shareUrlFor('foo'), 'https://x.test/l/foo');
  });
}
