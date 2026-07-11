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

This repo is also the canonical home for infrastructure shared by the two app
repos (auslan_dictionary, slsl_dictionary):

### dictionarylib_test_support

`dictionarylib_test_support/` is a sibling package holding the shared
integration-test suite bodies. The apps consume it as a **dev_dependency** via
git url + `path: dictionarylib_test_support`, pinned to the **same ref** as
their dictionarylib dependency — when repinning an app, update **both** refs to
the same commit. Each app keeps thin `integration_test/*_test.dart` stubs plus
two config files (`integration_test/test_config.dart`,
`integration_test/multi_device/md_config.dart`).

### Reusable GitHub workflows (.github/workflows/app-*.yaml)

Called from the app repos via
`uses: banool/dictionarylib/.github/workflows/<name>@main`:

- `app-format.yaml` — dart format gate. Inputs: `working_directory`,
  `flutter_version`, `format_paths`. No secrets.
- `app-release-android.yaml` — flutter test (+ optionally build appbundle and
  upload to the Play internal track). Inputs: `package_name` (required),
  `working_directory`, `flutter_version`, `publish` (false = test-only).
  Secrets: `UPLOAD_KEYSTORE`, `KEY_PROPERTIES`, `ANDROID_SERVICE_ACCOUNT_JSON`.
- `app-web-deploy.yaml` — Flutter web build → Cloudflare Pages. Inputs:
  `project_name`, `production_branch` (both required), `working_directory`,
  `flutter_version`. Secrets: `CLOUDFLARE_API_TOKEN` (required),
  `CLOUDFLARE_ACCOUNT_ID` (optional; non-secret literal fallback baked in).
- `app-pages-deploy.yaml` — static site → Cloudflare Pages. Inputs:
  `project_name`, `production_branch` (required), `working_directory`
  (default `site`), `node_version`. Same secrets as app-web-deploy.

Note: editing a reusable workflow here never triggers the app CIs. After a
change, bump the app's `.force` sentinel (ci) or `gh workflow run` (web/pages,
they keep workflow_dispatch) to exercise it.

### Shared scripts (scripts/)

Resolved by the apps via the sibling-checkout convention (a `dictionarylib`
clone next to the app repo), overridable with `DICTIONARYLIB_DIR`:

- `scripts/multi_device_run.sh` — canonical multi-device e2e driver. Each
  app's `integration_test/multi_device/run.sh` is a ~15-line wrapper setting
  `MD_APP_DIR`, `MD_BUNDLE_ID`, `MD_ANDROID_PKG`, `MD_APP_ID`.
- `scripts/ios_publish.sh` — canonical TestFlight build/upload (auth
  precheck, invalid-cert/profile cleanup, automatic signing, `--beta`
  promotion). Each app's `ios/publish.sh` is a wrapper setting
  `PUBLISH_APP_DIR`, `PUBLISH_BUNDLE_ID`, `PUBLISH_BETA_GROUP`.
- `scripts/appstore_beta.py` — App Store Connect beta promotion, invoked by
  `ios_publish.sh --beta`. Fully env-var configured, stdlib-only.
- `scripts/take_screenshots_lib.py` / `scripts/upload_screenshots_lib.py` —
  canonical store-screenshot capture/upload. Each app's
  `screenshots/take_screenshots.py` and `screenshots/upload_screenshots.py`
  are wrappers that import these via `sys.path` and call
  `configure(...)` + `main()` with the app's device matrix, locale maps,
  bundle ids, and poster-video source.

### Copy-pair policy: .githooks/pre-commit and bump_version.sh

The canonical shapes live in this repo; the apps carry deliberate byte-similar
copies (this can't ship through a pub dependency). The apps' `bump_version.sh`
bumps **patch + build number**; this repo's variant bumps patch only (a library
has no build number) — that difference is intentional. The bump is
unconditional on every commit **by design**: CI builds and uploads store
releases on a broad set of changes, and store uploads reject a reused version
code. Never gate the bump behind a path filter.
