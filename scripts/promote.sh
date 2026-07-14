#!/bin/bash
#
# Promote an already-uploaded dictionary-app build to a wider audience — the
# beta testers or the general public — on iOS (App Store / TestFlight) and
# Android (Google Play).
#
# This is the canonical implementation, shared by the dictionary apps; each
# app's promote.sh is a thin wrapper that sets the PROMOTE_* env below and execs
# this. Run the wrapper, not this file.
#
# It assumes a build was already uploaded (iOS: `ios/upload.sh` put a build on
# the internal TestFlight track; Android: CI published to the Play internal
# track). It does NOT build or upload anything — it selects the latest uploaded
# build and promotes it to the stage you pick with the mandatory --stage flag:
#
#   --stage beta       Wider beta audience. Handles "What to Test" notes.
#     iOS      -> set the build's "What to Test" notes, add it to the external
#                 TestFlight group ($PROMOTE_BETA_GROUP), submit for Beta App Review.
#     Android  -> promote the internal-track versionCode to the beta track
#                 ($PROMOTE_ANDROID_BETA_TRACK, default "beta") with release notes.
#
#   --stage external   General public release. Handles "What's New" notes.
#     iOS      -> attach the build to its App Store version, set "What's New",
#                 releaseType AFTER_APPROVAL, and submit for App Store review.
#     Android  -> promote the internal-track versionCode to the production track
#                 at 100% with release notes, and commit.
#
# Usage (via the wrapper):
#   ./promote.sh --stage beta [notes-file]        # both platforms
#   ./promote.sh --stage external [notes-file]
#   ./promote.sh --stage external --dry-run       # plan only, touch nothing
#   ./promote.sh --stage beta --ios-only | --android-only
#   ./promote.sh --stage external --yes           # skip the confirmation prompt
#   ./promote.sh --stage external --no-submit     # iOS: prepare but don't submit
#   ./promote.sh --stage external --no-commit     # Android: prepare but don't commit
#   ./promote.sh --stage external --rollout=0.2   # Android: staged rollout
#
# A [notes-file] positional supplies the notes for both stores. For --stage
# external, omitting it uses a generic default. For --stage beta, external
# TestFlight testers require "What to Test" notes, so if you omit the file you'll
# be prompted for them up front.
#
# Required env (the wrapper sets these):
#   PROMOTE_APP_DIR        absolute path to the Flutter app directory
#   PROMOTE_BUNDLE_ID      iOS bundle id, e.g. com.banool.auslanDictionary
#   PROMOTE_PACKAGE_NAME   Android package, e.g. com.banool.auslan_dictionary
# Optional env:
#   PROMOTE_BETA_GROUP           external TestFlight group (required for --stage beta on iOS)
#   PROMOTE_ANDROID_BETA_TRACK   Play track for --stage beta (default "beta")
#   PLAY_SERVICE_ACCOUNT_JSON_PATH  Play key (default: <app>/android/play_service_account.json)

set -euo pipefail

for var in PROMOTE_APP_DIR PROMOTE_BUNDLE_ID PROMOTE_PACKAGE_NAME; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var must be set (run this via the app's promote.sh wrapper)" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSTORE_RELEASE="$SCRIPT_DIR/appstore_release.py"
APPSTORE_BETA="$SCRIPT_DIR/appstore_beta.py"
PLAY_RELEASE="$SCRIPT_DIR/play_release.py"
DEFAULT_NOTES="Assorted improvements and bug fixes."
ANDROID_BETA_TRACK="${PROMOTE_ANDROID_BETA_TRACK:-beta}"

# --- args -------------------------------------------------------------------
STAGE=""
DRY_RUN=0
IOS=1
ANDROID=1
ASSUME_YES=0
SUBMIT=1
COMMIT=1
ROLLOUT=""
NOTES_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="${2:-}"; shift 2 ;;
    --stage=*) STAGE="${1#--stage=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --ios-only) ANDROID=0; shift ;;
    --android-only) IOS=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-submit) SUBMIT=0; shift ;;
    --no-commit) COMMIT=0; shift ;;
    --rollout=*) ROLLOUT="${1#--rollout=}"; shift ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) NOTES_FILE="$1"; shift ;;
  esac
done

case "$STAGE" in
  beta|external) ;;
  "") echo "error: --stage is required (--stage beta or --stage external)" >&2; exit 1 ;;
  *) echo "error: --stage must be 'beta' or 'external', got '$STAGE'" >&2; exit 1 ;;
esac

cd "$PROMOTE_APP_DIR"

# --- release notes ----------------------------------------------------------
# external -> "What's New"; beta -> "What to Test". A notes-file supplies either;
# external falls back to a generic default, beta prompts (external TestFlight
# testers require notes).
if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || { echo "notes file not found: $NOTES_FILE" >&2; exit 1; }
  NOTES="$(cat "$NOTES_FILE")"
  [[ -n "${NOTES//[[:space:]]/}" ]] || { echo "notes file is empty: $NOTES_FILE" >&2; exit 1; }
elif [[ "$STAGE" == external ]]; then
  NOTES="$DEFAULT_NOTES"
else
  echo "==> --stage beta needs 'What to Test' notes for the external testers."
  echo "    Type them now, then finish with an empty line (or Ctrl-D):"
  NOTES=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    NOTES+="$line"$'\n'
  done
  NOTES="${NOTES%$'\n'}"
  [[ -n "${NOTES//[[:space:]]/}" ]] || { echo "No 'What to Test' notes entered — aborting." >&2; exit 1; }
fi

# --- version / build number (X.Y.Z+N) ---------------------------------------
VERSION_STRING="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+.*$/\1/')"
BUILD_NUMBER="$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*$/\1/')"

# --- iOS credentials (same scheme as ios/upload.sh) -------------------------
if [[ "$IOS" == 1 ]]; then
  # App Store Connect credentials (renamed from ios/publish.env; the old name
  # still works as a fallback).
  ENV_FILE="ios/secrets.env"
  [[ -f "$ENV_FILE" ]] || ENV_FILE="ios/publish.env"
  [[ -f "$ENV_FILE" ]] || { echo "error: ios/secrets.env not found in $PROMOTE_APP_DIR" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  [[ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] && { echo 'Please set APP_STORE_CONNECT_API_ISSUER_ID in ios/secrets.env' >&2; exit 1; }
  [[ -z "${API_KEY_PATH:-}" ]] && { echo 'Please set API_KEY_PATH in ios/secrets.env' >&2; exit 1; }
  [[ ! -f "$API_KEY_PATH" ]] && { echo "API key not found at $API_KEY_PATH" >&2; exit 1; }
  KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
  _kf="$(basename "$API_KEY_PATH")"
  if [[ "$_kf" == AuthKey_*.p8 ]]; then _kf="${_kf#AuthKey_}"; KEY_ID="${_kf%.p8}"; fi
  [[ -z "$KEY_ID" ]] && { echo "Set APP_STORE_CONNECT_API_KEY_ID or name the key AuthKey_<ID>.p8" >&2; exit 1; }
  if [[ "$STAGE" == beta ]]; then
    [[ -z "${PROMOTE_BETA_GROUP:-}" ]] && { echo "error: PROMOTE_BETA_GROUP must be set for --stage beta (the external TestFlight group)" >&2; exit 1; }
    [[ -f "$APPSTORE_BETA" ]] || { echo "error: $APPSTORE_BETA not found" >&2; exit 1; }
  else
    [[ -f "$APPSTORE_RELEASE" ]] || { echo "error: $APPSTORE_RELEASE not found" >&2; exit 1; }
  fi
fi

# --- Android credentials ----------------------------------------------------
PLAY_KEY="${PLAY_SERVICE_ACCOUNT_JSON_PATH:-$PROMOTE_APP_DIR/android/play_service_account.json}"
if [[ "$STAGE" == external ]]; then TO_TRACK="production"; else TO_TRACK="$ANDROID_BETA_TRACK"; fi
if [[ "$ANDROID" == 1 ]]; then
  [[ -f "$PLAY_RELEASE" ]] || { echo "error: $PLAY_RELEASE not found" >&2; exit 1; }
  if [[ ! -f "$PLAY_KEY" ]]; then
    echo "error: Play service-account key not found at $PLAY_KEY" >&2
    echo "       Drop the CI publishing service account's JSON there, or set" >&2
    echo "       PLAY_SERVICE_ACCOUNT_JSON_PATH. (Same account as the" >&2
    echo "       ANDROID_SERVICE_ACCOUNT_JSON CI secret; needs permission to" >&2
    echo "       release to the '$TO_TRACK' track in the Play Console.)" >&2
    exit 1
  fi
fi

ROLLOUT_DESC="100% (completed)"
[[ -n "$ROLLOUT" ]] && ROLLOUT_DESC="staged ($ROLLOUT)"

# --- summary + confirm ------------------------------------------------------
echo "======================================================================"
echo "  Promote: $PROMOTE_BUNDLE_ID"
echo "  Stage:   $STAGE"
echo "  Version: $VERSION_STRING  (build $BUILD_NUMBER)"
echo "  Build:   latest already uploaded (internal track)"
if [[ "$STAGE" == external ]]; then
  [[ "$IOS" == 1 ]] && echo "  iOS:     App Store, releaseType AFTER_APPROVAL, submit=$([[ $SUBMIT == 1 ]] && echo yes || echo no)"
  [[ "$ANDROID" == 1 ]] && echo "  Android: Play production, rollout $ROLLOUT_DESC, commit=$([[ $COMMIT == 1 ]] && echo yes || echo no)"
else
  [[ "$IOS" == 1 ]] && echo "  iOS:     TestFlight group '$PROMOTE_BETA_GROUP', submit for Beta App Review=$([[ $SUBMIT == 1 ]] && echo yes || echo no)"
  [[ "$ANDROID" == 1 ]] && echo "  Android: Play '$TO_TRACK' track, rollout $ROLLOUT_DESC, commit=$([[ $COMMIT == 1 ]] && echo yes || echo no)"
fi
echo "  Notes:   ${NOTES%%$'\n'*}"
[[ "$DRY_RUN" == 1 ]] && echo "  MODE:    DRY RUN (nothing will be changed)"
echo "======================================================================"

if [[ "$DRY_RUN" != 1 && "$ASSUME_YES" != 1 ]]; then
  if [[ "$STAGE" == external ]]; then
    warn="This SUBMITS to the App Store / COMMITS to Play production."
  else
    warn="This sends the build to the '$PROMOTE_BETA_GROUP' TestFlight group / Play '$TO_TRACK' track."
  fi
  read -r -p "$warn Continue? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

FAILED=""

# --- iOS --------------------------------------------------------------------
if [[ "$IOS" == 1 ]]; then
  echo
  if [[ "$STAGE" == external ]]; then
    echo "==> iOS: promoting the latest TestFlight build to the App Store..."
    if ASC_BUNDLE_ID="$PROMOTE_BUNDLE_ID" \
       ASC_SELECT="latest" \
       ASC_VERSION_STRING="$VERSION_STRING" \
       ASC_WHATS_NEW="$NOTES" \
       ASC_RELEASE_TYPE="AFTER_APPROVAL" \
       ASC_SUBMIT="$SUBMIT" \
       ASC_DRY_RUN="$DRY_RUN" \
       APP_STORE_CONNECT_API_KEY_ID="$KEY_ID" \
       APP_STORE_CONNECT_API_ISSUER_ID="$APP_STORE_CONNECT_API_ISSUER_ID" \
       API_KEY_PATH="$API_KEY_PATH" \
       python3 "$APPSTORE_RELEASE"; then
      echo "==> iOS: OK"
    else
      echo "==> iOS: FAILED" >&2
      FAILED="$FAILED ios"
    fi
  else
    echo "==> iOS: promoting the latest TestFlight build to the '$PROMOTE_BETA_GROUP' group..."
    if ASC_BUNDLE_ID="$PROMOTE_BUNDLE_ID" \
       ASC_BUILD_NUMBER="$BUILD_NUMBER" \
       ASC_GROUP_NAME="$PROMOTE_BETA_GROUP" \
       ASC_WHATS_NEW="$NOTES" \
       ASC_SUBMIT="$SUBMIT" \
       ASC_DRY_RUN="$DRY_RUN" \
       APP_STORE_CONNECT_API_KEY_ID="$KEY_ID" \
       APP_STORE_CONNECT_API_ISSUER_ID="$APP_STORE_CONNECT_API_ISSUER_ID" \
       API_KEY_PATH="$API_KEY_PATH" \
       python3 "$APPSTORE_BETA"; then
      echo "==> iOS: OK"
    else
      echo "==> iOS: FAILED" >&2
      FAILED="$FAILED ios"
    fi
  fi
fi

# --- Android ----------------------------------------------------------------
if [[ "$ANDROID" == 1 ]]; then
  echo
  echo "==> Android: promoting the internal-track build to the '$TO_TRACK' track..."
  if PLAY_SERVICE_ACCOUNT_JSON_PATH="$PLAY_KEY" \
     PLAY_PACKAGE_NAME="$PROMOTE_PACKAGE_NAME" \
     PLAY_FROM_TRACK="internal" \
     PLAY_TO_TRACK="$TO_TRACK" \
     PLAY_VERSION_CODE="$BUILD_NUMBER" \
     PLAY_RELEASE_NOTES="$NOTES" \
     PLAY_ROLLOUT="$ROLLOUT" \
     PLAY_COMMIT="$COMMIT" \
     PLAY_DRY_RUN="$DRY_RUN" \
     python3 "$PLAY_RELEASE"; then
    echo "==> Android: OK"
  else
    echo "==> Android: FAILED" >&2
    FAILED="$FAILED android"
  fi
fi

echo
if [[ -n "$FAILED" ]]; then
  echo "Promote finished with failures:$FAILED" >&2
  exit 1
fi
echo "Promote complete."
