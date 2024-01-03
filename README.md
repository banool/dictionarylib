# Dictionary Lib

## Dev guide
When first pulling this repo, add this to `.git/hooks/pre-commit`:
```
#!/bin/bash

./bump_version.sh
git add pubspec.yaml
```

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
