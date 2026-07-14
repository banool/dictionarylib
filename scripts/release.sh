#!/bin/bash
#
# Promote already-uploaded beta builds to full store releases — iOS (App Store)
# and Android (Google Play) — for a dictionary app.
#
# This is the canonical implementation, shared by the dictionary apps; each
# app's release.sh is a thin wrapper that sets the RELEASE_* env below and execs
# this. Run the wrapper, not this file.
#
# It assumes a beta upload already happened (iOS: `ios/publish.sh --beta` put a
# build in TestFlight; Android: CI published to the Play internal track). It does
# NOT build or upload anything — it selects the latest beta build and promotes it:
#   iOS      -> attach the build to its App Store version, set "What's New",
#               releaseType AFTER_APPROVAL, and submit for App Store review.
#   Android  -> promote the internal-track versionCode to the production track at
#               100% with release notes, and commit.
#
# Usage (via the wrapper):
#   ./release.sh [notes-file]        # both platforms, real submit/commit
#   ./release.sh --dry-run           # plan only, touch nothing
#   ./release.sh --ios-only | --android-only
#   ./release.sh --yes               # skip the confirmation prompt
#   ./release.sh --no-submit         # iOS: prepare but don't submit for review
#   ./release.sh --no-commit         # Android: prepare but don't commit
#   ./release.sh --rollout=0.2       # Android: staged rollout instead of 100%
# A [notes-file] positional arg supplies release notes for both stores; without
# one, a generic default is used.
#
# Required env (the wrapper sets these):
#   RELEASE_APP_DIR        absolute path to the Flutter app directory
#   RELEASE_BUNDLE_ID      iOS bundle id, e.g. com.banool.auslanDictionary
#   RELEASE_PACKAGE_NAME   Android package, e.g. com.banool.auslan_dictionary
# Optional env:
#   PLAY_SERVICE_ACCOUNT_JSON_PATH  Play key (default: <app>/android/play_service_account.json)

set -euo pipefail

for var in RELEASE_APP_DIR RELEASE_BUNDLE_ID RELEASE_PACKAGE_NAME; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var must be set (run this via the app's release.sh wrapper)" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSTORE_RELEASE="$SCRIPT_DIR/appstore_release.py"
PLAY_RELEASE="$SCRIPT_DIR/play_release.py"
DEFAULT_NOTES="Assorted improvements and bug fixes."

# --- args -------------------------------------------------------------------
DRY_RUN=0
IOS=1
ANDROID=1
ASSUME_YES=0
SUBMIT=1
COMMIT=1
ROLLOUT=""
NOTES_FILE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --ios-only) ANDROID=0 ;;
    --android-only) IOS=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --no-submit) SUBMIT=0 ;;
    --no-commit) COMMIT=0 ;;
    --rollout=*) ROLLOUT="${arg#--rollout=}" ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) NOTES_FILE="$arg" ;;
  esac
done

cd "$RELEASE_APP_DIR"

# --- release notes ----------------------------------------------------------
if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || { echo "notes file not found: $NOTES_FILE" >&2; exit 1; }
  NOTES="$(cat "$NOTES_FILE")"
  [[ -n "${NOTES//[[:space:]]/}" ]] || { echo "notes file is empty: $NOTES_FILE" >&2; exit 1; }
else
  NOTES="$DEFAULT_NOTES"
fi

# --- version / build number (X.Y.Z+N) ---------------------------------------
VERSION_STRING="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+.*$/\1/')"
BUILD_NUMBER="$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*$/\1/')"

# --- iOS credentials (same scheme as ios/publish.sh) ------------------------
if [[ "$IOS" == 1 ]]; then
  [[ -f ios/publish.env ]] || { echo "error: ios/publish.env not found in $RELEASE_APP_DIR" >&2; exit 1; }
  # shellcheck disable=SC1091
  . ./ios/publish.env
  [[ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]] && { echo 'Please set APP_STORE_CONNECT_API_ISSUER_ID in ios/publish.env' >&2; exit 1; }
  [[ -z "${API_KEY_PATH:-}" ]] && { echo 'Please set API_KEY_PATH in ios/publish.env' >&2; exit 1; }
  [[ ! -f "$API_KEY_PATH" ]] && { echo "API key not found at $API_KEY_PATH" >&2; exit 1; }
  KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
  _kf="$(basename "$API_KEY_PATH")"
  if [[ "$_kf" == AuthKey_*.p8 ]]; then _kf="${_kf#AuthKey_}"; KEY_ID="${_kf%.p8}"; fi
  [[ -z "$KEY_ID" ]] && { echo "Set APP_STORE_CONNECT_API_KEY_ID or name the key AuthKey_<ID>.p8" >&2; exit 1; }
  [[ -f "$APPSTORE_RELEASE" ]] || { echo "error: $APPSTORE_RELEASE not found" >&2; exit 1; }
fi

# --- Android credentials ----------------------------------------------------
PLAY_KEY="${PLAY_SERVICE_ACCOUNT_JSON_PATH:-$RELEASE_APP_DIR/android/play_service_account.json}"
if [[ "$ANDROID" == 1 ]]; then
  [[ -f "$PLAY_RELEASE" ]] || { echo "error: $PLAY_RELEASE not found" >&2; exit 1; }
  if [[ ! -f "$PLAY_KEY" ]]; then
    echo "error: Play service-account key not found at $PLAY_KEY" >&2
    echo "       Drop the CI publishing service account's JSON there, or set" >&2
    echo "       PLAY_SERVICE_ACCOUNT_JSON_PATH. (Same account as the" >&2
    echo "       ANDROID_SERVICE_ACCOUNT_JSON CI secret; needs 'Release to" >&2
    echo "       production' permission in the Play Console.)" >&2
    exit 1
  fi
fi

ROLLOUT_DESC="100% (completed)"
[[ -n "$ROLLOUT" ]] && ROLLOUT_DESC="staged ($ROLLOUT)"

# --- summary + confirm ------------------------------------------------------
echo "======================================================================"
echo "  Release: $RELEASE_BUNDLE_ID"
echo "  Version: $VERSION_STRING  (build $BUILD_NUMBER)"
echo "  Build:   latest beta already uploaded"
[[ "$IOS" == 1 ]] && echo "  iOS:     App Store, releaseType AFTER_APPROVAL, submit=$([[ $SUBMIT == 1 ]] && echo yes || echo no)"
[[ "$ANDROID" == 1 ]] && echo "  Android: Play production, rollout $ROLLOUT_DESC, commit=$([[ $COMMIT == 1 ]] && echo yes || echo no)"
echo "  Notes:   ${NOTES%%$'\n'*}"
[[ "$DRY_RUN" == 1 ]] && echo "  MODE:    DRY RUN (nothing will be changed)"
echo "======================================================================"

if [[ "$DRY_RUN" != 1 && "$ASSUME_YES" != 1 ]]; then
  read -r -p "This SUBMITS to the App Store / COMMITS to Play production. Continue? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

FAILED=""

# --- iOS --------------------------------------------------------------------
if [[ "$IOS" == 1 ]]; then
  echo
  echo "==> iOS: promoting the latest TestFlight build to the App Store..."
  if ASC_BUNDLE_ID="$RELEASE_BUNDLE_ID" \
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
fi

# --- Android ----------------------------------------------------------------
if [[ "$ANDROID" == 1 ]]; then
  echo
  echo "==> Android: promoting the internal-track build to production..."
  if PLAY_SERVICE_ACCOUNT_JSON_PATH="$PLAY_KEY" \
     PLAY_PACKAGE_NAME="$RELEASE_PACKAGE_NAME" \
     PLAY_FROM_TRACK="internal" \
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
  echo "Release finished with failures:$FAILED" >&2
  exit 1
fi
echo "Release complete."
