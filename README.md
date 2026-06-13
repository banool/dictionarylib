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
