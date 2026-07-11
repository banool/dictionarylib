#!/usr/bin/env python3
"""Promote an already-uploaded TestFlight build to a full App Store release.

Run after a beta upload (see release.sh). Talks to the App Store Connect API:
picks the build to release (the latest one in TestFlight, or an exact build
number), finds or creates the editable App Store version for that build's
marketing version, attaches the build, sets the "What's New" release notes,
sets the release type, and submits the version for App Store review.

Self-contained: standard library only. The ES256 JWT is signed with `openssl`,
so there are no pip dependencies. Mirrors appstore_beta.py's style.

Config comes from the environment (release.sh sets these):
  APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, API_KEY_PATH
  ASC_BUNDLE_ID          iOS bundle id, e.g. com.banool.auslanDictionary
  ASC_SELECT             "latest" (default) or "number"
  ASC_BUILD_NUMBER       required when ASC_SELECT=number (the +N build number)
  ASC_VERSION_STRING     optional marketing version fallback (X.Y.Z); normally
                         taken from the selected build itself
  ASC_WHATS_NEW          release notes text (required)
  ASC_NOTES_SCOPE        "all" (default, every existing localization) | "en"
  ASC_RELEASE_TYPE       AFTER_APPROVAL (default) | MANUAL | SCHEDULED
  ASC_SUBMIT             "1" (default) submit for review | "0" prepare only
  ASC_DRY_RUN            "1" plan only, no writes | "0" (default)
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
POLL_TIMEOUT_S = 30 * 60
POLL_INTERVAL_S = 20

# States in which a version's metadata can still be edited (and so a build
# attached / notes set / submitted). Apple doesn't publish this list; it matches
# what fastlane's spaceship used and what upload_screenshots_lib.py relies on.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
    "INVALID_BINARY",
}
# States that mean the version is already on its way / live — nothing to do.
DONE_STATES = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_DEVELOPER_RELEASE",
    "PENDING_APPLE_RELEASE",
    "PROCESSING_FOR_APP_STORE",
    "READY_FOR_SALE",
    "READY_FOR_DISTRIBUTION",
}


def die(msg):
    print(f"\n[appstore_release] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def env(name):
    value = os.environ.get(name)
    if not value:
        die(f"missing required env var {name}")
    return value


def log(msg):
    print(f"[appstore_release] {msg}", flush=True)


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _der_to_raw(der):
    # openssl emits an ECDSA signature as DER (SEQUENCE of two INTEGERs); JOSE
    # (ES256) wants raw r||s, 32 bytes each. P-256 sigs are short, so all the
    # ASN.1 lengths are single-byte (short form).
    if not der or der[0] != 0x30:
        die("unexpected signature encoding from openssl")
    i = 2  # skip SEQUENCE tag + length byte
    if der[i] != 0x02:
        die("bad signature (expected INTEGER for r)")
    rlen = der[i + 1]
    r = der[i + 2 : i + 2 + rlen]
    i = i + 2 + rlen
    if der[i] != 0x02:
        die("bad signature (expected INTEGER for s)")
    slen = der[i + 1]
    s = der[i + 2 : i + 2 + slen]
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    return r + s


class Client:
    """App Store Connect client with token re-mint (a release run can outlast
    the 20-minute JWT life while polling review state)."""

    def __init__(self):
        self.key_id = env("APP_STORE_CONNECT_API_KEY_ID")
        self.issuer = env("APP_STORE_CONNECT_API_ISSUER_ID")
        self.key_path = env("API_KEY_PATH")
        self._token = None
        self._token_born = 0.0

    def token(self):
        if self._token is None or time.monotonic() - self._token_born > 15 * 60:
            now = int(time.time())
            header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
            payload = {
                "iss": self.issuer,
                "iat": now,
                "exp": now + 1200,
                "aud": "appstoreconnect-v1",
            }
            signing_input = (
                b64url(json.dumps(header, separators=(",", ":")).encode())
                + "."
                + b64url(json.dumps(payload, separators=(",", ":")).encode())
            )
            proc = subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", self.key_path],
                input=signing_input.encode(),
                capture_output=True,
            )
            if proc.returncode != 0:
                die("openssl signing failed: " + proc.stderr.decode(errors="replace"))
            self._token = signing_input + "." + b64url(_der_to_raw(proc.stdout))
            self._token_born = time.monotonic()
        return self._token

    def call(self, method, path, body=None, params=None):
        url = path if path.startswith("http") else API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = {"errors": [{"detail": raw.decode(errors="replace")}]}
            return exc.code, parsed

    def get_all(self, path, params=None):
        """GET a collection, following pagination."""
        items = []
        st, data = self.call("GET", path, params=params)
        if st != 200:
            return st, data, items
        while True:
            items.extend(data.get("data", []))
            nxt = (data.get("links") or {}).get("next")
            if not nxt:
                return st, data, items
            st, data = self.call("GET", nxt)
            if st != 200:
                return st, data, items


def err_detail(data):
    errors = data.get("errors", []) if isinstance(data, dict) else []
    joined = "; ".join(
        f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ") for e in errors
    )
    return joined or json.dumps(data)[:800]


def version_state(v):
    a = v.get("attributes", {})
    return a.get("appVersionState") or a.get("appStoreState")


def select_build(client, app_id, select, build_number):
    """Return (build_id, build_number, marketing_version), waiting for the build
    to finish processing."""
    params = {
        "filter[app]": app_id,
        "limit": "1",
        "include": "preReleaseVersion",
        "fields[builds]": "version,processingState,uploadedDate,preReleaseVersion",
        "fields[preReleaseVersions]": "version",
    }
    if select == "number":
        params["filter[version]"] = build_number
    else:
        params["sort"] = "-uploadedDate"

    what = f"build {build_number}" if select == "number" else "the latest build"
    log(f"selecting {what} and waiting for it to finish processing...")
    deadline = time.time() + POLL_TIMEOUT_S
    while time.time() < deadline:
        st, data = client.call("GET", "/v1/builds", params=params)
        if st != 200:
            die(f"could not query builds: {err_detail(data)}")
        builds = data.get("data", [])
        if not builds:
            log("  not visible yet (App Store Connect is still ingesting it)...")
            time.sleep(POLL_INTERVAL_S)
            continue
        build = builds[0]
        state = build["attributes"]["processingState"]
        num = build["attributes"].get("version")
        log(f"  build {num}: {state}")
        if state == "VALID":
            # Marketing version comes from the linked preReleaseVersion.
            marketing = None
            rel = (
                build.get("relationships", {})
                .get("preReleaseVersion", {})
                .get("data")
            )
            if rel:
                for inc in data.get("included", []):
                    if inc["type"] == "preReleaseVersions" and inc["id"] == rel["id"]:
                        marketing = inc["attributes"].get("version")
            return build["id"], num, marketing
        if state in ("INVALID", "FAILED"):
            die(f"build {num} failed processing ({state})")
        time.sleep(POLL_INTERVAL_S)
    die("timed out waiting for the build to finish processing")


def find_or_create_version(client, app_id, version_string, dry_run):
    st, data, versions = client.get_all(
        f"/v1/apps/{app_id}/appStoreVersions",
        params={"filter[platform]": "IOS", "limit": "50"},
    )
    if st != 200:
        die(f"could not list App Store versions: {err_detail(data)}")
    match = next(
        (v for v in versions if v["attributes"].get("versionString") == version_string),
        None,
    )
    if match:
        state = version_state(match)
        if state in EDITABLE_STATES:
            log(f"reusing editable App Store version {version_string} ({state})")
            return match["id"], False
        if state in DONE_STATES:
            log(
                f"App Store version {version_string} is already {state} — "
                "nothing to submit. Exiting."
            )
            return match["id"], True
        die(
            f"App Store version {version_string} is in state {state}, which is "
            "neither editable nor a known submitted/released state; refusing to "
            "touch it."
        )
    # Not present -> create it.
    log(f"creating App Store version {version_string}")
    if dry_run:
        log("  [dry-run] would POST /v1/appStoreVersions")
        return None, False
    st, data = client.call(
        "POST",
        "/v1/appStoreVersions",
        body={
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    if st in (200, 201):
        return data["data"]["id"], False
    detail = err_detail(data)
    if st == 409 and "already exist" in detail.lower():
        # Raced or filter missed it; re-fetch.
        st2, d2, versions2 = client.get_all(
            f"/v1/apps/{app_id}/appStoreVersions",
            params={"filter[platform]": "IOS", "limit": "50"},
        )
        m2 = next(
            (v for v in versions2 if v["attributes"].get("versionString") == version_string),
            None,
        )
        if m2:
            return m2["id"], version_state(m2) not in EDITABLE_STATES
    die(
        f"could not create App Store version {version_string}: {detail}\n"
        "  (A version must be strictly greater than the last released one — "
        "did the build/version get bumped?)"
    )


def attach_build(client, version_id, build_id, dry_run):
    log("attaching the build to the version")
    if dry_run:
        log("  [dry-run] would PATCH the version's build relationship")
        return
    st, data = client.call(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        body={"data": {"type": "builds", "id": build_id}},
    )
    if st not in (200, 204):
        die(f"could not attach build: {err_detail(data)}")


def set_release_notes(client, version_id, notes, scope, dry_run):
    st, data, locs = client.get_all(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        params={"limit": "50"},
    )
    if st != 200:
        die(f"could not list localizations: {err_detail(data)}")
    if not locs:
        die("the version has no localizations to set 'What's New' on")
    targets = locs
    if scope == "en":
        targets = [l for l in locs if l["attributes"]["locale"].startswith("en")] or locs
    names = ", ".join(l["attributes"]["locale"] for l in targets)
    log(f"setting release notes on: {names}")
    if dry_run:
        log("  [dry-run] would PATCH whatsNew on those localizations")
        return
    for loc in targets:
        st, data = client.call(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{loc['id']}",
            body={
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": {"whatsNew": notes},
                }
            },
        )
        if st not in (200, 201):
            die(
                f"could not set release notes for {loc['attributes']['locale']}: "
                f"{err_detail(data)}"
            )


def set_release_type(client, version_id, release_type, dry_run):
    log(f"setting release type to {release_type}")
    if dry_run:
        log("  [dry-run] would PATCH releaseType")
        return
    st, data = client.call(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}",
        body={
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {"releaseType": release_type},
            }
        },
    )
    if st != 200:
        die(f"could not set release type: {err_detail(data)}")


def submit_for_review(client, app_id, version_id, dry_run):
    log("submitting for App Store review")
    if dry_run:
        log("  [dry-run] would create a reviewSubmission, add the version, submit")
        return

    # 1. Find an open reviewSubmission or create one.
    submission_id = None
    st, data = client.call(
        "POST",
        "/v1/reviewSubmissions",
        body={
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    if st in (200, 201):
        submission_id = data["data"]["id"]
    elif st in (409, 422):
        log(f"  an open review submission already exists ({err_detail(data)}); reusing it")
        st2, d2, subs = client.get_all(
            "/v1/reviewSubmissions",
            params={
                "filter[app]": app_id,
                "filter[platform]": "IOS",
                "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES,COMPLETING",
                "limit": "10",
            },
        )
        # Pick a submission that is not yet submitted, else the newest.
        open_subs = [s for s in subs if not s["attributes"].get("submittedDate")]
        pool = open_subs or subs
        if pool:
            submission_id = pool[0]["id"]
    if not submission_id:
        die(f"could not create or find a review submission: {err_detail(data)}")
    log(f"  review submission -> {submission_id}")

    # 2. Add this version as an item on the submission (idempotent).
    st, data = client.call(
        "POST",
        "/v1/reviewSubmissionItems",
        body={
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": submission_id}
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    },
                },
            }
        },
    )
    if st in (200, 201):
        log("  added the version to the review submission")
    elif st in (409, 422) and "already" in err_detail(data).lower():
        log("  version is already an item on the submission")
    else:
        die(f"could not add version to review submission: {err_detail(data)}")

    # 3. Submit.
    st, data = client.call(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        body={
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    if st in (200, 201):
        log("  submitted for review")
    elif st in (409, 422) and (
        "already" in err_detail(data).lower() or "submitted" in err_detail(data).lower()
    ):
        log("  already submitted / in review")
    else:
        die(f"could not submit for review: {err_detail(data)}")


def main():
    bundle_id = env("ASC_BUNDLE_ID")
    select = os.environ.get("ASC_SELECT", "latest").strip() or "latest"
    build_number = os.environ.get("ASC_BUILD_NUMBER", "").strip()
    version_env = os.environ.get("ASC_VERSION_STRING", "").strip()
    notes = os.environ.get("ASC_WHATS_NEW", "").strip()
    notes_scope = os.environ.get("ASC_NOTES_SCOPE", "all").strip() or "all"
    release_type = os.environ.get("ASC_RELEASE_TYPE", "AFTER_APPROVAL").strip()
    submit = os.environ.get("ASC_SUBMIT", "1").strip() != "0"
    dry_run = os.environ.get("ASC_DRY_RUN", "0").strip() == "1"

    if select == "number" and not build_number:
        die("ASC_SELECT=number requires ASC_BUILD_NUMBER")
    if not notes:
        die("ASC_WHATS_NEW is empty — release notes are required")

    if dry_run:
        log("DRY RUN — no writes will be made")

    client = Client()

    # 1. App.
    st, data = client.call("GET", "/v1/apps", params={"filter[bundleId]": bundle_id})
    if st != 200 or not data.get("data"):
        die(f"could not find app {bundle_id}: {err_detail(data)}")
    app_id = data["data"][0]["id"]
    log(f"app {bundle_id} -> {app_id}")

    # 2. Build.
    build_id, num, marketing = select_build(client, app_id, select, build_number)
    version_string = marketing or version_env
    if not version_string:
        die(
            "could not determine the marketing version from the build; set "
            "ASC_VERSION_STRING"
        )
    if version_env and marketing and version_env != marketing:
        log(
            f"note: build's marketing version is {marketing}, pubspec says "
            f"{version_env}; using the build's ({marketing})"
        )
    log(f"build {num} is VALID -> {build_id} (marketing version {version_string})")

    # 3. Version.
    version_id, already_done = find_or_create_version(
        client, app_id, version_string, dry_run
    )
    if already_done:
        log("Done — this version is already submitted/released.")
        return
    if version_id is None and dry_run:
        log("Dry run complete (version would be created; downstream steps skipped).")
        return

    # 4-6. Attach build, notes, release type.
    attach_build(client, version_id, build_id, dry_run)
    set_release_notes(client, version_id, notes, notes_scope, dry_run)
    set_release_type(client, version_id, release_type, dry_run)

    # 7. Submit.
    if submit:
        submit_for_review(client, app_id, version_id, dry_run)
    else:
        log("ASC_SUBMIT=0 — prepared but not submitted for review")

    verb = "would be submitted" if dry_run else "submitted"
    tail = "" if dry_run else f" (releaseType={release_type})"
    log(f"\nDone — {bundle_id} {version_string} (build {num}) {verb} for review{tail}.")


if __name__ == "__main__":
    main()
