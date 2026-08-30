import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('playbackSpeedFromName', () {
    test('parses valid names', () {
      expect(
        playbackSpeedFromName('PointFiveZero'),
        PlaybackSpeed.PointFiveZero,
      );
      expect(playbackSpeedFromName('OneFiveZero'), PlaybackSpeed.OneFiveZero);
      expect(playbackSpeedFromName('One'), PlaybackSpeed.One);
    });

    test('falls back to 1x for unknown / null', () {
      expect(playbackSpeedFromName('TwoX'), PlaybackSpeed.One);
      expect(playbackSpeedFromName(''), PlaybackSpeed.One);
      expect(playbackSpeedFromName(null), PlaybackSpeed.One);
    });
  });

  group('getDefaultPlaybackSpeed', () {
    test('reads the persisted default', () async {
      SharedPreferences.setMockInitialValues({
        KEY_DEFAULT_PLAYBACK_SPEED: 'PointFiveZero',
      });
      sharedPreferences = await SharedPreferences.getInstance();
      expect(getDefaultPlaybackSpeed(), PlaybackSpeed.PointFiveZero);
    });

    test('falls back to 1x when unset or garbage', () async {
      SharedPreferences.setMockInitialValues({});
      sharedPreferences = await SharedPreferences.getInstance();
      expect(getDefaultPlaybackSpeed(), PlaybackSpeed.One);

      SharedPreferences.setMockInitialValues({
        KEY_DEFAULT_PLAYBACK_SPEED: 'garbage',
      });
      sharedPreferences = await SharedPreferences.getInstance();
      expect(getDefaultPlaybackSpeed(), PlaybackSpeed.One);
    });
  });
}
