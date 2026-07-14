#!/usr/bin/env python3
"""Promote an already-uploaded Play build from one track to another.

Run after CI has published the build to the internal track (see promote.sh).
Talks to the Google Play Developer API v3: opens an edit, reads the source
track (internal by default) to find the versionCode(s) to promote, writes them
into the target track (production by default) with release notes and the chosen
rollout, and commits the edit. If anything fails before the commit the edit is
discarded, so a failed run changes nothing.

Self-contained: standard library only. The service-account JWT is signed with
`openssl`, so there are no pip dependencies. Mirrors upload_screenshots_lib.py.

Config comes from the environment (promote.sh sets these):
  PLAY_SERVICE_ACCOUNT_JSON_PATH   path to the service-account JSON key
  PLAY_PACKAGE_NAME                Android package, e.g. com.banool.auslan_dictionary
  PLAY_FROM_TRACK                  source track (default "internal")
  PLAY_TO_TRACK                    target track (default "production", e.g. "beta")
  PLAY_VERSION_CODE                optional cross-check against pubspec +N
  PLAY_RELEASE_NOTES               release notes text (required)
  PLAY_NOTES_LANG                  BCP-47 language for the notes (default "en-US")
  PLAY_ROLLOUT                     "" = full 100% (completed) | 0<f<1 = staged
  PLAY_COMMIT                      "1" (default) commit | "0" prepare then discard
  PLAY_DRY_RUN                     "1" plan only, discard the edit | "0" (default)
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

PLAY_API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
PLAY_TOKEN_URL = "https://oauth2.googleapis.com/token"
PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def die(msg):
    print(f"\n[play_release] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def env(name):
    value = os.environ.get(name)
    if not value:
        die(f"missing required env var {name}")
    return value


def log(msg):
    print(f"[play_release] {msg}", flush=True)


def _b64url(data):
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _openssl_sign(key_path, message):
    res = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=message,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if res.returncode != 0:
        die("openssl signing failed: " + res.stderr.decode(errors="replace"))
    return res.stdout


def make_jwt(header, payload, sign):
    def compact(obj):
        return _b64url(json.dumps(obj, separators=(",", ":")).encode())

    signing_input = f"{compact(header)}.{compact(payload)}"
    return f"{signing_input}.{_b64url(sign(signing_input.encode()))}"


def http(method, url, *, headers=None, body=None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def play_access_token(key_path):
    """OAuth2 service-account JWT-bearer flow, no client libraries."""
    if not os.path.isfile(key_path):
        die(
            f"Play service account key not found at {key_path}. Drop a JSON key "
            "for the CI publishing service account there, or set "
            "PLAY_SERVICE_ACCOUNT_JSON_PATH."
        )
    info = json.loads(open(key_path).read())
    now = int(time.time())
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as f:
        f.write(info["private_key"])
        f.flush()
        assertion = make_jwt(
            {"alg": "RS256", "typ": "JWT"},
            {
                "iss": info["client_email"],
                "scope": PLAY_SCOPE,
                "aud": PLAY_TOKEN_URL,
                "iat": now,
                "exp": now + 3600,
            },
            lambda msg: _openssl_sign(f.name, msg),
        )
    st, raw = http(
        "POST",
        PLAY_TOKEN_URL,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        body=urllib.parse.urlencode(
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            }
        ).encode(),
    )
    if st != 200:
        die(f"could not get a Play access token (HTTP {st}): {raw.decode(errors='replace')}")
    return json.loads(raw)["access_token"], info.get("client_email", "?")


class Play:
    def __init__(self, token, package):
        self.token = token
        self.package = package

    def call(self, method, path, body=None):
        url = f"{PLAY_API}/applications/{self.package}{path}"
        headers = {"Authorization": f"Bearer {self.token}"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        st, raw = http(method, url, headers=headers, body=data)
        parsed = None
        if raw:
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = {"raw": raw.decode(errors="replace")}
        return st, parsed


def err(data, st):
    if isinstance(data, dict):
        e = data.get("error")
        if isinstance(e, dict):
            return f"{e.get('status', st)}: {e.get('message', '')}"
        if "raw" in data:
            return data["raw"][:800]
    return json.dumps(data)[:800] if data is not None else f"HTTP {st}"


def pick_source_release(track_obj):
    """Return (versionCodes, releaseNotes) for the release to promote: the
    completed release with the highest versionCode."""
    releases = track_obj.get("releases") or []
    completed = [r for r in releases if r.get("status") == "completed" and r.get("versionCodes")]
    if not completed:
        return None, None
    best = max(completed, key=lambda r: max(int(c) for c in r["versionCodes"]))
    return best["versionCodes"], best.get("releaseNotes")


def main():
    key_path = os.path.expanduser(env("PLAY_SERVICE_ACCOUNT_JSON_PATH"))
    package = env("PLAY_PACKAGE_NAME")
    from_track = os.environ.get("PLAY_FROM_TRACK", "internal").strip() or "internal"
    to_track = os.environ.get("PLAY_TO_TRACK", "production").strip() or "production"
    expect_code = os.environ.get("PLAY_VERSION_CODE", "").strip()
    notes = os.environ.get("PLAY_RELEASE_NOTES", "").strip()
    notes_lang = os.environ.get("PLAY_NOTES_LANG", "en-US").strip() or "en-US"
    rollout = os.environ.get("PLAY_ROLLOUT", "").strip()
    commit = os.environ.get("PLAY_COMMIT", "1").strip() != "0"
    dry_run = os.environ.get("PLAY_DRY_RUN", "0").strip() == "1"

    if not notes:
        die("PLAY_RELEASE_NOTES is empty — release notes are required")
    user_fraction = None
    if rollout:
        try:
            user_fraction = float(rollout)
        except ValueError:
            die(f"PLAY_ROLLOUT must be a number 0<f<1, got {rollout!r}")
        if not (0 < user_fraction < 1):
            die(f"PLAY_ROLLOUT must be 0<f<1, got {user_fraction}")

    if dry_run:
        log("DRY RUN — the edit will be opened, planned, then discarded")

    token, sa_email = play_access_token(key_path)
    log(f"authenticated as {sa_email}")
    play = Play(token, package)

    # 1. Open an edit.
    st, data = play.call("POST", "/edits")
    if st != 200:
        die(f"could not open a Play edit (HTTP {st}): {err(data, st)}")
    edit_id = data["id"]
    log(f"opened edit {edit_id}")

    def discard():
        s, _ = play.call("DELETE", f"/edits/{edit_id}")
        log(f"discarded edit {edit_id}" if s in (200, 204) else f"(edit {edit_id} left to expire)")

    try:
        # 2. Read the source track.
        st, src = play.call("GET", f"/edits/{edit_id}/tracks/{from_track}")
        if st != 200:
            die(f"could not read the {from_track} track (HTTP {st}): {err(src, st)}")
        version_codes, src_notes = pick_source_release(src)
        if not version_codes:
            die(
                f"no completed release with a versionCode on the {from_track} "
                f"track — has a build been uploaded there?"
            )
        top = max(int(c) for c in version_codes)
        log(f"{from_track} track has versionCode(s) {version_codes} -> promoting {top}")
        if expect_code and str(top) != expect_code:
            log(
                f"note: pubspec build number is {expect_code} but the {from_track} "
                f"track's latest is {top}; promoting {top} (the latest beta)"
            )

        # 3. Check the target track for a no-op.
        st, dst = play.call("GET", f"/edits/{edit_id}/tracks/{to_track}")
        if st == 200:
            for r in dst.get("releases") or []:
                if (
                    r.get("status") == "completed"
                    and str(top) in [str(c) for c in r.get("versionCodes") or []]
                ):
                    log(f"versionCode {top} is already live on the {to_track} track at 100% — nothing to do")
                    discard()
                    return

        # 4. Compose the target-track release.
        release = {
            "versionCodes": [str(top)],
            "releaseNotes": [{"language": notes_lang, "text": notes}],
        }
        if user_fraction is not None:
            release["status"] = "inProgress"
            release["userFraction"] = user_fraction
            plan = f"staged rollout at {user_fraction:.0%}"
        else:
            release["status"] = "completed"
            plan = "full 100% rollout"
        log(f"{to_track} release plan: versionCode {top}, {plan}, notes[{notes_lang}]")

        if dry_run:
            log(f"[dry-run] would PUT the {to_track} track and commit; discarding edit")
            discard()
            return

        # 5. Write the target track.
        st, data = play.call(
            "PUT",
            f"/edits/{edit_id}/tracks/{to_track}",
            body={"track": to_track, "releases": [release]},
        )
        if st != 200:
            if st == 403:
                die(
                    f"HTTP 403 writing the {to_track} track — the service account "
                    f"likely lacks the 'Release to {to_track}' permission in the "
                    "Play Console (it may only have store-listing edit rights).\n"
                    f"  detail: {err(data, st)}"
                )
            die(f"could not write the {to_track} track (HTTP {st}): {err(data, st)}")

        if not commit:
            log(f"PLAY_COMMIT=0 — prepared the {to_track} track but discarding (not committing)")
            discard()
            return

        # 6. Commit.
        st, data = play.call("POST", f"/edits/{edit_id}:commit")
        if st != 200:
            detail = err(data, st)
            low = detail.lower()
            if "already been used" in low or "already used" in low:
                log(f"versionCode {top} already used/live — treating as success")
                return
            if st == 403:
                die(
                    "HTTP 403 committing — the service account likely lacks the "
                    f"'Release to {to_track}' permission.\n  detail: {detail}"
                )
            die(f"could not commit the edit (HTTP {st}): {detail}")
        log(f"committed — versionCode {top} promoted to the {to_track} track ({plan})")
    except SystemExit:
        # die() already printed; drop the edit so a partial run leaves no trace.
        if not dry_run:
            discard()
        raise
    log(f"\nDone — {package} versionCode {top} is on its way to the {to_track} track.")


if __name__ == "__main__":
    main()
