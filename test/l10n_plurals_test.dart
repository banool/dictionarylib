import 'package:dictionarylib/l10n/app_localizations_en.dart';
import 'package:dictionarylib/l10n/app_localizations_si.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('plural rendering at count 0', () {
    // Sinhala's CLDR "one" plural category includes BOTH 0 and 1, and
    // gen-l10n compiles an arb's exact `=1{...}` branch into intl's
    // `one:` CATEGORY parameter — so in si, 0 lands in the `=1` branch.
    // Any numeral hardcoded there therefore renders for empty state too
    // ("වචන 1" on a 0-word list, a "1-day streak" at 0 days). The si arb
    // must use the placeholder in the =1 branch, never a literal 1.
    // English is immune (its "one" category is exactly 1), so its
    // literal-1 branches are fine and also asserted here as a control.
    test('si renders 0 as 0 despite 0 being in the "one" category', () {
      final si = DictLibLocalizationsSi();
      expect(si.listWordCount(0), 'වචන 0');
      expect(si.listWordCount(1), 'වචන 1');
      expect(si.searchResultCount(0), 'ප්‍රතිඵල 0');
      expect(si.revisionStreak(0), 'දින 0 ක අඛණ්ඩතාව');
      expect(si.revisionSignCount(0), 'සංඥා 0');
      expect(si.revisionFlashcardCount(0), 'ෆ්ලෑෂ්කාඩ් 0');
      expect(si.regionSubtitleRegionCount(0), 'කලාප 0');
      expect(si.listSavedVideoCount(0), 'වීඩියෝ 0ක් සුරැකිණි');
      expect(si.savedToListCount(0), 'ලැයිස්තු 0කට සුරකින ලදී');
    });

    test('en control: 0 takes the other branch, 1 the =1 branch', () {
      final en = DictLibLocalizationsEn();
      expect(en.listWordCount(0), '0 words');
      expect(en.listWordCount(1), '1 word');
    });
  });
}
