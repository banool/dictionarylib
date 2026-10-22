# Dictionary Lib

## Dev guide

Install the git hooks once after cloning — the pre-commit hook checks formatting and bumps the build number:
```sh
git config core.hooksPath .githooks
```

### Formatting

All Dart is formatted with `dart format` (its default style). The pre-commit hook blocks unformatted commits, CI (`.github/workflows/dart.yml`) runs `dart format --output=none --set-exit-if-changed lib test`, and `.zed/settings.json` keeps Zed's format-on-save in step. Format everything with `dart format lib test`.

## Localization
Run this when you change any of the files in lib/l10n:
```
flutter gen-l10n
dart fix --apply
```

## Generating entries (de)serialization code
```
flutter pub run build_runner build
```

## Shared lists

The client side of the shared-lists feature lives in `lib/sharing/`. The backend lives in a separate private repository.

## Shared app infrastructure

The shared release/CI tooling (reusable workflows, release/promote/screenshot scripts) used to live here; it moved to [banool/appci](https://github.com/banool/appci) in 2026-07, which serves all three apps (auslan_dictionary, slsl_dictionary, kombio_scorekeeper). This repo is back to being just the shared Flutter package, plus:

### dictionarylib_test_support

`dictionarylib_test_support/` is a sibling package holding the shared
integration-test suite bodies. The apps consume it as a **dev_dependency** via
git url + `path: dictionarylib_test_support`, pinned to the **same ref** as
their dictionarylib dependency — when repinning an app, update **both** refs to
the same commit. Each app keeps thin `integration_test/*_test.dart` stubs plus
two config files (`integration_test/test_config.dart`,
`integration_test/multi_device/md_config.dart`).

The suites are the apps' end-to-end tests: each starts the real app on a simulator, emulator or phone and drives it through the screen, on the device's real storage. A change to how the apps behave gets one, and they are run on both apps before a release. From the app's directory, `flutter test integration_test/<name>_test.dart -d <device>` runs one; each file is its own launch of the app on a fresh install. (An Android run that loses its connection to the emulator part way leaves the app and its data installed, and the next run then starts from whatever it left: `adb uninstall <package>` first.)

| Suite (`lib/suites/`) | What it covers |
|---|---|
| `lists_rename`, `default_list` | Renaming, reordering, deleting and naming lists; the default list (the one that starts out as "Favourites") behaving like any other except that it can't be deleted; the star going with the name; the names a list can't have or be shared under. |
| `default_list_migration` | The first launch on an install from before Favourites became an ordinary list: plain, with favourites shared, and (SLSL) in Sinhala. One test file per kind of install, because the move happens once per launch. |
| `save_video`, `saved_count` | Saving a single video to a list and the counts that follow from it. |
| `review_session`, `review_early_exit` | Revision: a full session, stepping back and forward, leaving early, what is stored; sessions over new, due and forgotten cards, capped and not; random revision. |
| `theme_picker`, `toast_dismiss` | Smaller pieces of UI. |
| `screenshot` | The store screenshots. |

`lib/multi_device/` holds the suites that need a server: `integration_test/multi_device/run.sh` in each app runs them against a local worker (`bunx wrangler dev --env dev` in the backend repo's `workers/`) on two devices. Phases A to D are two people sharing and editing one list. The solo runs are one person each: sharing their default list and revising from it straight away, a list of theirs arriving from another device, and a signed-in install with favourites shared taking the default-list update.

Note the screenshot suite here is coupled to appci: the slugs it captures must
match the `app_store_shots` / `play_shots` curation lists in the apps'
`screenshots/upload_screenshots.py`, and `_posterUrlFor` in
`lib/video_player_screen.dart` must keep matching `poster_name()` in appci's
`take_screenshots_lib.py`.

### Copy-pair policy: .githooks/pre-commit and bump_version.sh

Each repo carries its own copy of the pre-commit hook and `bump_version.sh`
(this can't ship through a pub dependency; appci holds the canonical reference
copy). The apps' `bump_version.sh` bumps **patch + build number**; this repo's
variant bumps patch only (a library has no build number) — that difference is
intentional. The bump is unconditional on every commit **by design**: CI builds
and uploads store releases on a broad set of changes, and store uploads reject
a reused version code. Never gate the bump behind a path filter.
