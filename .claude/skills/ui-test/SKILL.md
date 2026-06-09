---
name: ui-test
description: Drive and verify this Flutter dictionary app in the iOS Simulator end-to-end with no human in the loop — launch a screen, inspect the live UI, tap/type/swipe, and assert the result. Use when asked to "test the app", "drive the app", "verify in the simulator", "check the UI", "reproduce a UI bug", "screenshot the app", or to confirm a UI/UX change actually works on screen (not just `flutter test`). Built on the AXe CLI plus Flutter debug hooks. Read the generic `axe` skill for the full CLI; this skill is the project-specific loop and the Flutter gotchas.
---

# AI-driven UI testing for the dictionary app

This lets me close the loop entirely myself on the iOS Simulator: deep-link to a screen, read the real accessibility tree, act on it, and verify — no real device, no human tapping. Everything below was confirmed live against the running app, not assumed.

## Layout

- **App (runnable):** `~/github/auslan_dictionary` — `flutter run` happens here.
- **UI (shared):** `~/github/dictionarylib/lib` — most screens/widgets live here. Edit here, hot-reload picks it up.
- **AXe binary:** `/opt/homebrew/bin/axe` (Homebrew). Brew is **not** on the sandbox `PATH`, so call axe by its **full path**.

## Sandbox

Simulator interaction needs the real sim + network. Run every axe/simctl/flutter command with `dangerouslyDisableSandbox: true` — sandboxed runs fail with "Operation not permitted" against the simulator.

## The loop

1. **Find the booted sim** and keep its UDID in a shell var:
   ```bash
   xcrun simctl list devices booted          # -> e.g. iPhone 17 (54757059-...-13B2B8248197)
   UDID=54757059-0511-449C-8AF0-13B2B8248197
   ```
2. **Launch / deep-link** the screen you want (see "Debug launch hooks" below). If `flutter run` is already attached, prefer hot-reload over relaunching.
3. **Inspect** the live UI to get labels + tap coordinates (see "Inspecting the UI").
4. **Act** — `axe tap/type/swipe/batch` (full path, always `--udid $UDID`).
5. **Verify** — re-inspect with `describe-ui` (structure/orientation) or `screenshot` + Read the PNG (pixels).

## Debug launch hooks (deep-link to any screen)

`auslan_dictionary/lib/root.dart` reads three debug-only `--dart-define`s (ignored in release, default empty). These are the confirmed-real ones — there are no others wired up:

- `DEBUG_INITIAL_LOCATION` — a GoRouter location to boot straight into, e.g. `/revision`, `/search?query=dog&navigate_to_first_match=true`.
- `DEBUG_THEME_VARIANT` — `hearth` (default redesign) or `classic`.
- `DEBUG_THEME_MODE` — `light` or `dark`.

```bash
cd /Users/dport/github/auslan_dictionary && /Users/dport/.development/flutter/bin/flutter run \
  --dart-define=DEBUG_INITIAL_LOCATION=/revision \
  --dart-define=DEBUG_THEME_VARIANT=hearth \
  --dart-define=DEBUG_THEME_MODE=dark
```
The cwd resets between Bash calls, so `cd ... &&` in the **same** command. Use the absolute flutter path. To exercise a state that has no launch hook, add a temporary one in Dart, drive it, then **revert it** (don't leave debug hooks committed).

## Inspecting the UI

`describe-ui` dumps the full accessibility tree as JSON. Reduce it to just the actionable elements (type, label, value, stable id, tap-point) with this helper:

```bash
cat > "$TMPDIR/axeui.py" <<'PY'
import json,sys
d=json.load(sys.stdin); rows=[]
def walk(n):
    t=n.get("type"); lab=n.get("AXLabel"); val=n.get("AXValue"); uid=n.get("AXUniqueId")
    f=n.get("frame",{})
    if t in ("Button","TextField","StaticText","Image","SearchField","Cell","Link","Switch") and (lab or val):
        cx=int(f.get("x",0)+f.get("width",0)/2); cy=int(f.get("y",0)+f.get("height",0)/2)
        rows.append((t,(lab or "")[:34],(val or "")[:12],uid or "",f"{cx},{cy}"))
    for c in n.get("children",[]) or []: walk(c)
walk(d[0])
print(f"{len(rows)} elements:")
for t,lab,val,uid,xy in rows:
    print(f"  [{t:10}] {lab:34} val={val:12} @ {xy}{('  id='+uid) if uid else ''}")
PY
/opt/homebrew/bin/axe describe-ui --udid $UDID | python3 "$TMPDIR/axeui.py"
```

Then act with `tap`/`type`/`swipe`/`batch` — see the `axe` skill for syntax and selector-vs-coordinate guidance. One app-specific note: `type` only lands in a field you've already **tapped to focus** — tap the field first, then type. (Re-inspecting before a batch matters here because Flutter labels shift — see limitations.)

## Verifying orientation — read the AXFrame, NOT the screenshot

This was the key discovery, and it overturns the old "the simulator fakes orientation, you need a real device" belief. `SystemChrome.setPreferredOrientations` **does** genuinely rotate the app on the simulator, and `describe-ui` reports the **true** orientation via the root element's frame:

- Root frame `402 x 874` → **portrait**.
- Root frame `874 x 402` → **landscape**.

```bash
cat > "$TMPDIR/orient.py" <<'PY'
import json,sys
d=json.load(sys.stdin); fr=d[0]["frame"]; w,h=fr["width"],fr["height"]
print(f"root frame {w}x{h} -> {'LANDSCAPE' if w>h else 'PORTRAIT'}")
PY
/opt/homebrew/bin/axe describe-ui --udid $UDID | python3 "$TMPDIR/orient.py"
```

## Confirmed limitations (each one verified, not guessed)

- **Screenshots/recordings never rotate.** Every capture is the device's physical portrait framebuffer (`1206 x 2622px`) even when the app is truly in landscape — the *content* just rotates 90° inside the portrait image. So **never judge orientation from screenshot pixels**; use the `describe-ui` AXFrame above. Screenshots are still correct for layout/colour/content, just not for orientation.
- **describe-ui is slow (~0.5s/call), so polling can't catch sub-second transients.** A quick visual flash (e.g. "screen rotates and snaps back on close") will be over before the next sample lands. For transient state, instead: (a) add `printAndLog(...)` at the relevant points and read the `flutter run` console, or (b) poll the AXFrame in a tight loop with no sleeps (each call ~0.4s) right after the action — concatenate the P/L samples and any `L` is a flash.
- **In-app `SystemChrome.setPreferredOrientations` dirties the simulator's device-orientation sensor; a real device's doesn't.** On the sim, forcing the app to landscape also moves the sim's "device orientation", so later *restoring* free rotation re-evaluates against that stale sensor and flicks the screen to landscape and back — a flash that does NOT happen on a real device held still (its physical sensor never moved). So **device-orientation-forcing logic (force + restore) cannot be trusted on the sim** — verify it on a real device, or sidestep it: rotating content with a `RotatedBox` looks identical on a full-screen video overlay and touches no orientation API, so it's clean on sim and device alike. (You can pin/read the sim's hardware orientation via the Simulator's `Device ▸ Orientation` menu through AppleScript — `osascript ... click menu item "Portrait" of menu 1 of menu item "Orientation" ...` — useful for isolating sensor-vs-API effects.)
- **Flutter widgets usually expose `AXUniqueId: null`,** so `tap --id` rarely works. Target by `--label` or coordinate. To get a stable id, add `Semantics(identifier: 'foo')` in the Dart widget, then `tap --id foo`.
- **Semantics types/labels are whatever Flutter emits and they shift with state.** Search-result rows come through as `StaticText`, not `Button`, so don't over-constrain with `--element-type`; tappable text may need a coordinate tap. Labels also change as the UI updates (e.g. a "Clear" button appears/disappears), which is why you re-inspect before each batch.

## Reference

- Generic AXe CLI usage: the `axe` skill.
- XcodeBuildMCP exposes `screenshot`/`snapshot_ui`/`describe-ui` too, but its tap/swipe tools only register once the AXe binary is detected at MCP startup. The AXe CLI here needs no MCP restart and is the more capable path — prefer it.
