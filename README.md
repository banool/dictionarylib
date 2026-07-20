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
