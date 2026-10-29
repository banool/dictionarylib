# Account sync: lists and revision progress

Plan written 2026-10-28 and reviewed the same day. Daniel's answers are folded in: merge silently, no off switch, followed lists sync, no compaction for now. This is the build spec: it names tables, routes, storage keys, algorithms and tests, so that the implementation follows it rather than reinterprets it. Nothing here is built yet. It covers both apps, since everything lives in dictionarylib and the Cloudflare Worker in dictionary_backend.

Read before building: `lib/sharing/sync_engine.dart`, `lib/sharing/synced_entry_list.dart`, `lib/lists_service.dart`, `lib/list_storage.dart`, `lib/flashcards_logic.dart`, `lib/page_flashcards_landing.dart`, `lib/page_flashcards.dart` in dictionarylib, and `workers/src/list_do.ts`, `index.ts`, `storage.ts`, `validation.ts` in dictionary_backend.

## 1. What we're building

Someone who signs in gets all their lists, the lists they follow and their flashcard progress on every device they sign in on. Their own lists stay private unless they share them. The app keeps working entirely offline, every change is saved on the device first, and syncing happens in the background without blocking anything. Bad networks, an app killed mid-sync and two devices edited at once must never lose or duplicate data.

Out of scope: the web app and Android TV (no sign-in there); app settings such as theme and playback speed.

Two rules that hold everywhere (Daniel, 2026-10-29): nothing a signed-in person does on the device waits for the network, since most people use one device and the sync is a bonus for the few who use two; and when two devices disagree, the app resolves it by itself, by timestamps where the later intent is well defined (names, order, the default list, settings, delete against later edits) and by set union otherwise (signs, follows, answers), and never asks the person to sort it out or tells them it happened.

## 2. Decisions

1. **Signing in is syncing.** No separate opt-in, no off switch, no prompt at first launch. Signing out stops it on that device. Sharing needs a sign-in, so sharing one list means all of that person's lists and progress sync; the share dialog's sign-in step says so.
2. **A private list is an ordinary server list with a visibility flag.** Every list someone owns becomes a list Durable Object (DO), as shared lists are today, marked `private` or `shared`. That reuses the whole existing engine: the op queue, retries, missed-op catch-up and conflict handling. Sharing flips the flag; nothing is copied.
3. **"Stop sharing" makes a list private.** Followers see it as deleted by its owner (as today, via the public snapshot going away) and editors lose access. The owner keeps it syncing.
4. **One per-person DO, the account DO,** holds what isn't a list: the directory (the person's lists, their order, which is the default), follows, flashcard history, random-mode totals and revision settings. It is the only creator of private lists, so two devices signing in at the same moment can't each create "Animals".
5. **Signing in merges silently, never replaces** (Daniel, 2026-10-28). The device's default list merges into the account's default list, a list with the same name as one on the account merges into it (union of signs), everything else uploads as a new list. A sign removed on one device before signing in can come back; that is the price of never losing anything.
6. **Deleting a list deletes it on every device,** and the confirmation says so. The server keeps a deleted list 30 days and can restore it; Cloudflare's point-in-time recovery covers every DO for 30 days as a backstop.
7. **Flashcard history stays on the device as it is, and the server keeps a full copy.** No compaction anywhere for now (Daniel, 2026-10-28). Every device ends up with every answer from every device; schedules and the progress page are computed from that as today. The analysis of dropping history is under "Deferred".
8. **Keep the operating system's backups, but make restored installs safe** (section 5.10).
9. **The interim list offer goes away when sync ships.** The interim check (`checkAccountLists`, the "Review" snackbar, `AccountListsRecord`) is uncommitted in the main checkout and may ship on its own first; this work builds on `HEAD` without it and never needs it.
10. **Kill switches at both ends:** a server env var that makes account routes answer 503, and a live app knob through the existing `readKnob` plumbing.
11. **Old app versions must stay safe forever,** since store builds lag for months. In particular an old build's "stop sharing" (a `DELETE`) must not delete a list from the person's new devices (section 4.2).
12. **Random-mode totals sync as events,** not per-device counters, so a restored or cloned device can't double count (section 5.8).
13. **Follows sync** (Daniel, 2026-10-28): the Subscribed tab is the same on every device.
14. **No first-launch nudge, iPad or otherwise.** The only discovery hooks are the Settings account section and a tappable line under My lists when signed out.

## 3. Cost

From Auslan's last 28 days, scaled to a month. Analytics IDs reset daily, so these are device-days and sessions, not people.

| Per month | Today | Worst case: every session syncs | Included in the Workers Paid plan |
|---|---|---|---|
| Sessions | about 57,000 | | |
| Worker requests | | about 400,000 | 10M |
| DO requests | | about 340,000 | 1M |
| Rows written (list edits and flashcard answers) | | about 210,000 | 50M |
| R2 operations | | about 150,000 | 1M free |
| New flashcard history | 1.5 MB | | |
| Storage, all lists and five years of history | | under 1 GB | 5 GB |

Even ten times today's traffic stays inside the included amounts apart from DO requests, which would cost well under a dollar a month. The one-time upload when people first sign in is small: five years of everyone's history at today's pace is about 1.5 million answers, 90 MB.

## 4. Backend (dictionary_backend/workers)

### 4.1 Compatibility rules

- Every existing route keeps its shape and meaning for old clients. New fields on responses are additive; old clients read only the keys they know.
- New clients send `x-sync-capabilities: account-sync` on every request. The Worker reads it in exactly one place: `DELETE /v1/lists/:id` (section 4.2). Everything else is decided by data, not by who is asking.
- Private lists never appear in the `owners/<hash>/<listId>` R2 index. That index now means "shared lists this person owns": it is written when a list is created shared or flipped to shared, and removed when a list goes private or is deleted. So `GET /v1/my-lists` needs no gating: old clients can't see private lists because they aren't there, and `MAX_LISTS_PER_USER` keeps counting shared lists only, as its name and message say.
- The account DO's directory is the authority for which lists a person owns, private and shared. The owners index is reconciled into it on every account sync (section 4.4), so a list shared from an old build appears on the person's new devices without the old build changing.

### 4.2 Old builds and `DELETE /v1/lists/:id`

Today an old build's "stop sharing" calls `DELETE`, which tombstones the list; the old build keeps its local copy. Under decision 6 a tombstoned list would then vanish from the person's new devices, which is data loss from their point of view. So:

- A `DELETE` **without** the capability header, for a list whose owner has an account directory (the account DO answers `hasDirectory()`; one DO call, only on this path), is carried out as "make private": the list DO sets `visibility = 'private'`, removes editors, invites, the public snapshot and the owner index marker, and the response is `204` as before. The old build removes its wrapper and keeps its local list exactly as today. When that build is updated, the sign-in merge links the local list to the private server list by name, so nothing duplicates.
- A `DELETE` without the header for an owner with no directory (someone who has never used a new build) tombstones as today, now with the 30-day purge alarm.
- A `DELETE` **with** the header is a real delete: tombstone, `deleted_at = now`, purge alarm, index markers removed, and the account DO marks the directory row deleted.

### 4.3 List DO (`list_do.ts`)

**Schema v3.** `DO_SCHEMA_VERSION = 3`. `initSchema` adds to `list_state`: `visibility TEXT NOT NULL DEFAULT 'shared'` and `deleted_at INTEGER` (null while live). Add columns with `ALTER TABLE ... ADD COLUMN` guarded by `PRAGMA table_info(list_state)`, then update `do_meta.schema_version` to 3. Existing lists therefore load as `shared`, which is what they are. `exportState` picks the new columns up unchanged.

**`init`** gains `visibility: 'private' | 'shared'` (absent means `shared`, which is what old clients get). Idempotent for the owner: if `list_state` exists, is not tombstoned and `owner_user_id === identity.userId`, return `doOk` with the existing `{listId, lastSeq, createdAt, updatedAt, existed: true}` instead of `ID_COLLISION`. Anything else that exists is `ID_COLLISION` as today. The Worker returns 200 for `existed`, 201 otherwise. Private lists are not published to R2 and get no owner index marker.

**Reserved names.** Split `validateDisplayName` into the shape check (length, always) and the reserved-name check, applied only when the list is or becomes shared: `POST /v1/lists` with `visibility: 'shared'` (the default), `PUT /v1/lists/:id` on a shared list, and `PUT /v1/lists/:id/visibility` to `shared` (checked against the new name if one is given, else the current name). A private list may be called Favourites, which is what every default list is called.

**`addEntries` op** for `/sync`: `{type: 'addEntries', args: {entries: [{entry, video}, ...]}}`, 1 to 200 entries, accepted only while `visibility === 'private'` (otherwise `rejected` with `reasonCode: 'not_private'`). Applies like that many `addEntry` ops: skips pairs already present, enforces the cap, writes one `op_log` row and advances `seq` once. Because only private lists accept it and a private list has no editors, no old build ever receives this op type in `missedOps`. One op counts as one against `MAX_OPS_PER_BATCH`.

**`rename` op** for `/sync`: `{type: 'rename', args: {displayName}}`, owner only (an editor's is `rejected` with `reasonCode 'forbidden'`), shape-checked, and reserved-name-checked only while the list is shared (`rejected`, `reasonCode 'reserved'`). Last intent wins: `list_state` gains `display_name_ts` (the clamped client timestamp of the rename that set the name; the clamp is `min(clientTs, serverNow + 300)`, as for `resetProgress`), and a rename whose timestamp is older than it is `applied` without changing the name (`reasonCode 'stale'`). The new name reaches every device through the `displayName` every `/sync` response already echoes, so old builds need nothing. `PUT /v1/lists/:id` stays for old builds and sets `display_name_ts` to the server time.

**Caps.** `MAX_ENTRIES` (500) applies to shared lists; `MAX_ENTRIES_PRIVATE = 5000` to private ones. Flipping to shared with more than 500 entries is refused with `INVALID_BODY`, `details.reason: 'list_too_large_to_share'`, `details.limit: 500`.

**`setVisibility(visibility, displayName | undefined, identity, origin)`**, owner only, tombstoned → `GONE`.
- To `private`: delete every `editors` row and its `editors/<hash>/<listId>` marker, delete every invite, remove the owner index marker, delete the R2 snapshot and invalidate the cache. Write one synthetic `op_log` row (`type 'setVisibility'`, `client_op_id 'synthetic:visibility:private:<seq>'`) so other devices of the owner see the change in `missedOps`; clients treat unknown op types as no-ops today, and new clients act on this one.
- To `shared`: reserved-name check; entry-count check; apply `displayName` if given (same rules as rename); add the owner index marker; publish the snapshot; synthetic `op_log` row as above.
- Unchanged visibility is a no-op returning the current snapshot.
- `/sync` and `/state` responses gain `visibility`, echoed like `displayName`.

**Soft delete.** `deleteList` keeps its signature plus `{legacy: boolean}`. On a real delete: `tombstoned = 1`, `deleted_at = now`, snapshot and markers removed as today, and an alarm armed for `deleted_at + 30 days`. The `alarm()` handler already prunes invites; extend it: if tombstoned and `deleted_at` is 30 days old or more, `ctx.storage.deleteAll()` and return (with `compatibility_date` 2026-05-01 that also clears the alarm). Otherwise re-arm for whichever is sooner: the next invite expiry or the purge time.

**`restore(identity)`**, owner only, requires `tombstoned = 1` and a live DO: clears `tombstoned` and `deleted_at`, sets `visibility = 'private'` (followers were already told it was gone), re-arms the alarm for invites only. Returns the snapshot.

**Account deletion purges**: `purge()` RPC (no identity; the Worker has verified the session and the account DO's directory says the caller owns it) removes markers and the snapshot and calls `deleteAll()`. Followers see 404 and orphan after three polls, as they do today once a tombstoned list's snapshot is gone. This is a change from today's forever-tombstone: deleted accounts leave nothing behind.

### 4.4 Account DO (`account_do.ts`, class `AccountDO`, binding `ACCOUNT_DO`)

One per person per app, id `idFromName` of the string `<APP_ID>:<userIdHash>` (the hash `storage.ts` already uses for R2 keys). New `[[migrations]]` entry `tag = "v2"`, `new_sqlite_classes = ["AccountDO"]` in all three envs. The Worker passes a verified `CallerIdentity` and the request origin; the DO calls list DOs itself through `env.LIST_DO` where a change spans both.

Tables (`CREATE TABLE IF NOT EXISTS`, schema version 1 in a `do_meta` row):

```
meta        (id=1, schema_version, created_at, last_seq INTEGER NOT NULL DEFAULT 0, reset_ts_us INTEGER NOT NULL DEFAULT 0)
directory   (list_id TEXT PRIMARY KEY, position INTEGER NOT NULL, is_default INTEGER NOT NULL DEFAULT 0, visibility TEXT NOT NULL, name_cached TEXT NOT NULL, request_id TEXT UNIQUE, state TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER)
follows     (list_id TEXT PRIMARY KEY, followed_at INTEGER NOT NULL)
reviews     (master TEXT NOT NULL, combination TEXT NOT NULL, ts_us INTEGER NOT NULL, rating INTEGER NOT NULL, seq INTEGER NOT NULL, PRIMARY KEY (master, combination, ts_us)); CREATE INDEX reviews_by_seq ON reviews(seq)
random_sessions (op_id TEXT PRIMARY KEY, count INTEGER NOT NULL, ts_us INTEGER NOT NULL, seq INTEGER NOT NULL)
settings    (key TEXT PRIMARY KEY, value TEXT NOT NULL, seq INTEGER NOT NULL, updated_at INTEGER NOT NULL)
op_log      (seq INTEGER PRIMARY KEY, client_op_id TEXT NOT NULL UNIQUE, client_id TEXT NOT NULL, type TEXT NOT NULL, server_ts INTEGER NOT NULL)
```

`directory.state` is `creating`, `live` or `deleted`. `meta.last_seq` advances once per applied op; `reviews.seq` and `random_sessions.seq` record the op that inserted the row, which is what "everything after N" is cut on. The `op_log` keeps the last 500 ids as the list DO does; a replay beyond that is harmless because every op below is idempotent in effect (set semantics, max, or a primary key).

**`sync(body, identity, origin, ownedSharedIds, editorIds)`** is the one RPC behind `POST /v1/account/sync`. Body: `{clientId, sinceSeq, ops}`, at most 50 ops and 64 KB. The Worker lists `owners/<hash>/` and `editors/<hash>/` first (two R2 lists per call) and passes the ids in. Steps, in order:

1. Reconcile: insert a `live`, `shared` directory row (position after the last) for each id in `ownedSharedIds` with no row. Rows are never removed by reconciliation.
2. Apply each op in order (`duplicate` if its id is in `op_log`, else `applied` or `rejected` with `reason` and `reasonCode`), each in its own try so one bad op doesn't fail the batch. Op types:
   - `createList {requestId, listId, name, visibility: 'private'}`: if a row has this `requestId`, answer with its `listId` (`created: false`). Else if a `live` row's `name_cached` equals `name` after `normalizeName` (trim, lowercase, collapse runs of whitespace), answer with that `listId` (`created: false`). Else validate `listId` (`validateListId`) and the name shape, refuse if the number of `live` rows is at `MAX_PRIVATE_LISTS_PER_USER = 300` (`reasonCode 'list_limit'`), insert the row as `creating`, call `LIST_DO.init({listId, displayName: name, entries: [], visibility: 'private'}, identity, origin)`; on `ok` (created or `existed`) set `state = 'live'` and answer `{listId, created: true}`; on `ID_COLLISION` delete the row and answer `rejected` with `reasonCode 'id_collision'` (the client picks a new id); on any other failure leave the row `creating` and answer `rejected` with `reasonCode 'retry'` (the client retries with the same request id, which finds the row and re-runs `init`, which is idempotent).
   - `setDefault {listId}`: the row must be `live`; clears `is_default` on the others. Last intent wins by clamped client timestamp (`meta.default_ts`); an older op is `applied` with `reasonCode 'stale'` and changes nothing.
   - `reorder {listIds}`: assigns positions 1..n to the listed `live` ids in that order; unlisted live rows keep their relative order after them. Last intent wins by clamped client timestamp (`meta.order_ts`), `stale` as above.
   - `rename {listId, name}`: updates `name_cached` only (the list DO is the authority for the name; this keeps `createList`'s name match current). The Worker also sends this to the account DO after a successful `PUT /v1/lists/:id` so old-build renames reach the directory too.
   - `delete {listId}`: calls `LIST_DO.deleteList(identity, origin, {legacy: false})`; `ok`, `NOT_FOUND` and `GONE` all count as done; then sets the row `deleted`, `deleted_at = now`, `deleted_client_ts` = the op's clamped client timestamp (what a device with unsent edits compares against, section 5.5). The default list is refused (`reasonCode 'default_list'`). Order matters: the list first, so a crash between the two leaves a tombstoned list whose directory row is cleaned up by `unlink` later.
   - `unlink {listId}`: for a device that got 410 or three 404s on a linked list. Verified: calls `LIST_DO.getState(identity)`; only `NOT_FOUND`, `GONE` or `FORBIDDEN` mark the row `deleted`; `ok` answers `rejected` with `reasonCode 'still_live'` and the device keeps the list.
   - `restore {listId}`: row must be `deleted`; calls `LIST_DO.restore(identity)`; on `ok` the row is `live`, `visibility = 'private'`, position after the last.
   - `follow {listId}` / `unfollow {listId}`: upsert or delete in `follows`; at most `MAX_FOLLOWS = 500`.
   - `addReviews {reviews: [{m, c, r, t}, ...]}`: 1 to 500 items; `m` 1 to 1300 chars, `c` matches `^\d@@@\d$`, `r` an integer 0 to 3, `t` an integer. Rows with `t < meta.reset_ts_us` are skipped (`rejectedBeforeReset` count). Others are `INSERT OR IGNORE`d in chunks of 20 rows (the DO's 100-bound-variable limit) with `seq = last_seq + 1`. The result carries `{accepted, duplicates, rejectedBeforeReset}`.
   - `resetProgress {tsUs}`: `reset_ts_us = max(reset_ts_us, tsUs)`; deletes `reviews` and `random_sessions` with `ts_us < tsUs`.
   - `randomSession {count, tsUs}`: `INSERT OR IGNORE` keyed by the op id, skipped if `tsUs < reset_ts_us`; `count` 1 to 10000.
   - `setSetting {key, value}`: `key` from the allowlist in section 5.8 only, `value` a JSON string of at most 4 KB; upsert with the new `seq`. Last intent wins by clamped client timestamp (`settings.client_ts`), `stale` as above.
3. Build the response (every call, even with no ops): `{seq: last_seq, results, directory: [{listId, position, isDefault, visibility, name, state, deletedAt, deletedClientTs}], follows: [listId...], settings: [{key, value, seq}], resetTsUs, randomTotal (sum of count), reviews: up to 1000 rows with seq > sinceSeq ascending as [{m, c, r, t, seq}], randomSessions: rows with seq > sinceSeq, hasMore, editorListIds}`. The directory includes `deleted` rows with a `deletedAt` (the device uses them and the Recently deleted screen will); rows purged more than 30 days ago are removed by the device-independent cleanup below.
4. Housekeeping on each call: delete `deleted` directory rows whose `deleted_at` is older than 30 days; trim `op_log` to 500.

Other RPCs: `hasDirectory()` (any row exists), `noteRename(listId, name)`, `noteVisibility(listId, visibility)`, `noteDeleted(listId)` (used by the legacy delete path), `wipe()` for account deletion: for every directory row in any state call `LIST_DO.purge()` (`NOT_FOUND` counts as done), then `ctx.storage.deleteAll()`.

### 4.5 Worker routes (`index.ts`)

| Route | Change |
|---|---|
| `POST /v1/account/sync` | New. Session + app id; lists the two R2 indexes; forwards to `AccountDO.sync`. |
| `PUT /v1/lists/:id/visibility` | New. Body `{visibility, displayName?}`. For `shared`, `countOwnedListIds` against `MAX_LISTS_PER_USER` first (as create does). Then `ListDO.setVisibility`, then `AccountDO.noteVisibility`. Returns the snapshot. |
| `POST /v1/lists/:id/restore` | New. `ListDO.restore` then the account DO `restore` op's directory half (`noteRestored`). |
| `DELETE /v1/lists/:id` | Section 4.2. |
| `PUT /v1/lists/:id` | After success, `AccountDO.noteRename`. |
| `DELETE /v1/account` | `AccountDO.wipe()` first, then the existing owner and editor index loops (which now find only shared lists not already purged; `NOT_FOUND` is fine), then the user record. |
| `GET /v1/my-lists`, `POST /v1/lists`, `/sync`, `/state`, invites, editors | Unchanged for callers. |

New error code `UNAVAILABLE` → 503 in `errors.ts`. New `details.reason` values: `account_sync_disabled`, `list_too_large_to_share`. New op `reasonCode`s: `not_private`, `list_limit`, `id_collision`, `retry`, `default_list`, `still_live`.

**Kill switch.** Env var `ACCOUNT_SYNC_ENABLED = "true"` in every env's `[vars]`. When it is anything but `"true"`, `POST /v1/account/sync`, `PUT .../visibility` and `POST .../restore` answer `UNAVAILABLE` with `details.reason: 'account_sync_disabled'` and `Retry-After: 3600`. Flipping it is an edit to `wrangler.toml` and a push (CI deploys in minutes), or `bunx wrangler deploy --env auslan --var ACCOUNT_SYNC_ENABLED:false` by hand.

**Limits added to `validation.ts`:** `MAX_ENTRIES_PRIVATE`, `MAX_ADD_ENTRIES_PER_OP = 200`, `MAX_PRIVATE_LISTS_PER_USER = 300`, `MAX_REVIEWS_PER_OP = 500`, `MAX_FOLLOWS = 500`, `MAX_SETTING_VALUE_BYTES = 4096`, `ACCOUNT_SYNC_PAGE = 1000`.

### 4.6 Recovery

- `scripts/restore_do.ts`: given an app, a DO class, an id name and a time, calls an admin-gated route `POST /v1/admin/do/:class/:name/restore-to` that runs `getBookmarkForTime`, `onNextSessionRestoreBookmark` and `ctx.abort()`. Gated by `ADMIN_TOKEN` like the export routes. PITR doesn't run under `wrangler dev`, so rehearse on a deployed `--env dev` before launch and write the steps into `RUNBOOK.md`. Confirm during the rehearsal that a DO emptied with `deleteAll()` can still be restored to a point before the delete; the plan assumes it can.
- `scripts/backup.ts` learns to export account DOs: `GET /v1/admin/accounts` (hashes from the `users/` prefix) and `GET /v1/admin/accounts/:hash/export`.

### 4.7 Backend tests

Unit (`bun test`, DO stubbed as today) and integration (`wrangler dev`):
- `init` idempotency: same owner twice → 200 `existed`; different owner → 409.
- Reserved names: private list called Favourites is created; flipping it to shared is refused; renaming a shared list to Favourites is refused.
- `addEntries`: applied on private; rejected `not_private` on shared; cap at 5000; chunking at 200.
- Visibility: shared→private removes editors, markers, snapshot, invites; public GET is 404 afterwards; editor's `/sync` is 403; private→shared republishes, checks the 500 cap and the owner cap.
- Legacy `DELETE`: without the header and with a directory → private, 204, list still readable by the owner; without a directory → tombstoned; with the header → tombstoned with `deleted_at`.
- Soft delete: purge alarm after 30 days; `restore` before then brings it back private; restore after purge is 404.
- Account DO: every op type, idempotent on replay; `createList` by request id, by name, race of two creates with the same name from two "devices"; reorder; default list can't be deleted; `unlink` refused while live; reviews chunking and the 100-variable limit; reset cut-off against late answers; random sessions dedupe; settings allowlist; pagination at 1000 with `hasMore`; reconciliation of an owners-index list into the directory.
- Kill switch: 503 with the reason and `Retry-After`.
- Account deletion: private lists purged, account DO empty, indexes clean, repeat call is a no-op.

## 5. App (dictionarylib)

### 5.1 Storage

No schema version is bumped anywhere. `SyncedListMeta.fromJson` drops blobs whose `schemaVersion` differs, so every new field is optional with a default: `visibility` (`'shared'` when absent, which is right for every existing owner wrapper). `sharedSchemaVersion` stays 2.

New SharedPreferences keys (none shaped like a list key):
- `account_sync_state`: one JSON blob, written whole with a single `setString` so a crash leaves it consistent: `{schema: 1, userId, sinceSeq, mergePhase, linking: {localKey: {listId, requestId, step}}, unsyncable: {localKey: reason}, pendingOps: [...], followsGone: {listId: epochSecs}, randomTotal, lastSyncAt, pausedUntil}`. Removed on sign-out.
- `reviews_unsent`: a `List<String>` of encoded reviews (the `encodeReview` form) not yet acknowledged by the server. Appended by the single writer (section 5.8), drained by the controller.
- `install_marker` is not in prefs (section 5.10).

`KEY_SHARED_CLIENT_ID`, `KEY_SHARED_LIST_IDS` and the per-list meta and payload keys are unchanged.

### 5.2 The controller

`AccountSyncController` (`lib/sharing/account_sync.dart`), owned by `Sharing`, created in `Sharing.setup`, inert in `Sharing.disabled`. One `AsyncLock`. Entry point `kick(SyncReason reason)`: `startup` (3 s after the first frame, replacing `scheduleAccountListsCheckAfterStartup`), `resumed` (app lifecycle), `localChange` (debounced 2 s), `pullToRefresh` (immediate, bypasses backoff), `signedIn` (immediate), `paused` (flush only, best-effort, like `pushAllDirty`). A kick while a cycle runs sets a "run again" flag; the lock makes cycles strictly sequential.

A cycle, in order, each step skipped when it has nothing to do:
1. Guards: sharing enabled; not web, not Android TV; the `enable_account_sync` knob true (read via `readKnob(knobUrlBase, 'enable_account_sync', true)` in `extraStartupTasks`, cached in prefs as the mechanism already does); a session exists; `pausedUntil` in the past unless the reason is `pullToRefresh`.
2. If `account_sync_state.userId` is set and differs from the session's `userId`: `switchAccount()` (section 5.9), then continue as a first sign-in.
3. If `mergePhase != 'done'`: run the merge (section 5.4) from its saved step.
4. `sharing.engine.syncAll()` for linked lists (unchanged engine; per-list locks).
5. Account round trip: `POST /v1/account/sync` with up to 50 pending ops and the current `sinceSeq`; apply the response (section 5.5 to 5.8); if `hasMore`, repeat with no ops until it is false. Each page's rows are applied and `sinceSeq` saved before the next request.
6. Drain `reviews_unsent` in batches of 500 as `addReviews` ops (op id = first 32 hex chars of SHA-256 over the batch's lines, so a resend after a lost ack is a `duplicate`); remove a batch from `reviews_unsent` only after its op is `applied` or `duplicate`.
7. Save state; `sharing.bumpState()`; `lastSyncAt = now`.

Failure handling: a `SyncException` ends the cycle; `network` and `server` double a backoff from 2 s to 5 min, so a device left in the foreground syncs within five minutes of the network returning; a `localChange` kick while a retry is pending waits for it (never an early retry against a failing server), while `resumed`, `startup` and `pullToRefresh` reset the backoff and try at once; `rateLimited` and `unavailable` honour `Retry-After` (1 h for the kill switch); `unauthorized` drops the session as the engine does today and keeps all state. Account-sync requests get a 30 s timeout (a page of answers is up to about 100 KB). No snackbars, dialogs or banners from background cycles for any error kind; the Settings status line is the only place sync trouble shows (section 5.11). The engine's existing `snapshotCatchUp` notice is raised only for a shared list with at least one editor, since for a private list set semantics resolve a catch-up with nothing anyone needs to know.

List operations never wait on the controller's lock. The cycle holds the lock across its network calls, so a list operation that needs it (create, delete, rename of an unlinked list) pre-empts the cycle: every network await in a cycle is raced against "a list operation is waiting", and the moment one is, the step is abandoned, the in-flight response dropped unapplied, `_again` set and the lock released. Dropping a response is safe because every request is idempotent (resent list ops answer `duplicate`, `createList` carries its request id, answer batches have content-derived ids, account ops dedupe in the op log). A black-holed network (requests that never answer) must not delay any list operation by more than one turn of the event loop.

The membership-epoch machinery, `_changingMembership`, `ListsService.checkAccountLists`, `_oneAtATime` and `importEditableLists` are not needed: the controller serialises everything that changes which lists the device has. `importEditableLists` is replaced by the merge; the multi-device phase C and D suites change to sign in and let the merge run.

### 5.3 Link states

Every local list is in one of: `local` (no wrapper; signed out, or not yet reached), `linking` (an entry in `account_sync_state.linking`: `{listId, requestId, step: 'create' | 'seed'}` written before the first network call), `linked` (an owner-mode `SyncedEntryList` wrapper exists, `meta.visibility` private or shared), `unsyncable` (an entry in `unsyncable` with `too_large` or `kept_unsent`). Lists are linked one at a time under the controller lock. `ListsService.writableFor(list)` returns the wrapper when linked and the plain list otherwise; the save sheet, the word page and the list page already go through `ownedShareFor` and keep doing so.

Creating a list while signed in: `ListsService.createList(name)` creates the local list and the `linking` record in the same step, then kicks the controller. Both the create dialog and "copy to my lists" call it. Mutations before the link lands go to the plain list; when the seed is sent it carries the list's entries at that moment, and after the wrapper is inserted the controller diffs the local set against what was seeded and enqueues `addEntry` ops for anything added in between. `EntryList._assertNotOwnerShared` stays as is and keeps being true.

### 5.4 The sign-in merge

Runs under the controller lock with `mergePhase` saved after every step so a kill resumes where it was. Steps:

- **M0.** Save `userId`, `mergePhase = 'directory'`, `sinceSeq = 0`.
- **M1 directory.** `POST /v1/account/sync` with no ops. Keep the directory, follows, settings, `resetTsUs` and `editorListIds` in memory for the following steps (they are re-fetched on resume, which is fine).
- **M2 default list.** `K` = the device's default list key. If a wrapper for `K` exists, skip. If the directory has a default list `D`: link `K` to `D` with the wrapper's `displayName = D.name`, `visibility = D.visibility`, then merge (below). If not: send `createList {requestId, listId, name: K's name, visibility: 'private'}` and `setDefault {listId}` in one batch, with `requestId` and `listId` generated once and saved in `linking[K]` before sending; on `applied` insert the wrapper (`lastKnownSeq` from the create result, which for a found list means a `/state` fetch first), then seed. `mergePhase = 'lists'`.
- **M3 the device's other lists**, in display order, skipping linked and unsyncable ones. A list with more than 5000 signs is marked `unsyncable: too_large` and skipped. Otherwise look for a `live` directory row not yet linked on this device whose normalised name equals the list's normalised name (local names come from the key with underscores as spaces), first in directory order: link and merge. Otherwise `createList` with saved ids and seed. Seeding: `addEntries` ops of 200 through the wrapper's normal pending queue (the engine chunks at 50 ops a request, so a 5000-sign list is 25 ops in one request, well under 64 KB). After the loop, send one `reorder` with the directory's order followed by the newly created ids in device order, and set the local index to the same order with unsyncable lists at the end.
- **M4 the account's other lists.** For each `live` directory row with no wrapper here: `allocateLocalKey(preferredName: row.name, fallbackBase: importedListFallbackName)`, create the local list, fetch `/state`, fill it, insert the wrapper with `ownerFromSnapshot` and `visibility` from the row. `mergePhase = 'follows'`.
- **M5 follows.** For each account follow not on the device: `engine.subscribe(id)`; 404 or 410 → `followsGone[id] = now`. For each local subscription not in the account: enqueue `follow`. Editor lists: for each id in `editorListIds` not here as editor: fetch `/state`, install an editor mirror (today's `_applyAccountLists` editor branch, no question). `mergePhase = 'history'`.
- **M6 history.** `reviews_unsent = the whole stored history` (one `setStringList`). If the local random counter is above zero, enqueue `randomSession {count: counter, tsUs: KEY_FIRST_RANDOM_REVIEW or now}` with op id `random-initial-<clientId>` (so a sign-out and sign-in on the same device never double counts). For each synced setting (section 5.8): if the account has a value, apply it locally, else enqueue `setSetting` with the device's value. `mergePhase = 'done'`.
- Snackbar "Your lists and progress are now syncing." and analytics `sync_merge_completed` with bucketed list and answer counts.

Merging one list (M2 and M3): fetch `/state`; `remote = snapshot.entries`, `local = list.savedVideos`; add `remote − local` to the local set in server order (local extras keep their place after); enqueue `addEntries` (private) or `addEntry` per video (shared) for `local − remote`; set `lastKnownSeq = snapshot.lastSeq`; write entries then meta (the engine's ack order).

Names are not unique on the account; same-name matching only ever matches a row not yet linked on this device, so a device with "Pets" and an account whose default list is also "Pets" ends up with two lists called Pets, which is correct.

### 5.5 Lists in steady state

- **Save and remove** go through the wrapper as today (`addEntry` / `removeEntry` ops).
- **Rename** never waits for the network. Linked → set the wrapper's `displayName` at once, enqueue `rename {displayName}` in the list's own pending queue (so it flushes in order with the other ops) and a `rename` op for the account directory's cached name; the local key never moves. While a `rename` is pending, the `displayName` echoed by `/sync` responses is not adopted (it would be the old name from a partial batch). `local` → the existing key-move rename. `linking` → the key-move rename, and when the link lands with a different server name, a `rename` op with the local name. The wrapper's `displayName` is what every screen shows (`EntryList.getName()` already does this). Two devices renaming offline resolve on the server by timestamp; the loser adopts the echoed name on its next sync and nobody is told.
- **Reorder**: write the local index, enqueue `reorder` with the linked ids in the new order.
- **Delete**: the confirmation reads "Delete “{name}” from all your devices?". Then: remove the wrapper and the local list, enqueue `delete {listId}`. The "unshare first" rule goes: `SyncedEntryList.canBeDeleted()` returns `source.canBeDeleted()` for linked owner wrappers. A list in `linking` is deleted locally and `delete {listId}` is enqueued with the id chosen at link time (a no-op on the server if the create never landed). The default list stays undeletable.
- **Share**: `showShareDialog` keeps its pre-flight checks and the name field; on confirm it needs the list linked: if `linking`, it runs a controller cycle with the dialog's spinner and retries; if `unsyncable`, it refuses with the existing too-many-entries dialog. Then `PUT /visibility {visibility: 'shared', displayName}`; the wrapper's `visibility` and name update from the returned snapshot. "Shared by you" badges and the members page show only for `visibility == 'shared'`.
- **Stop sharing**: `PUT /visibility {visibility: 'private'}`; the list stays linked. Copy: "Stop sharing “{name}”? People following it lose access. It stays on your devices."
- **Deleted on another device** (a linked id present in the directory as `deleted`): resolved by timestamps, silently. If the wrapper has no pending ops, or its newest pending op is older than the row's `deletedClientTs`, the delete is the later intent: drop the edits, delete the local list and wrapper. If the newest pending op is newer than the delete, the edits are the later intent: enqueue `restore {listId}`, keep the wrapper, and flush the edits once the account answers `applied` (the list comes back on every device, with the edits). If the row is gone altogether (purged, or the server rewound) and the wrapper has pending ops, keep the local list as a plain `local` list, which the next cycle links again by name; without pending ops, delete it. No snackbar in any of these cases. The default list is never deleted this way (the server refuses deleting the default).
- **410, or three 404s**, on a linked list's `/sync`: the same local handling plus an `unlink` op. `_markOrphaned`'s editable branch changes accordingly; editor mirrors keep today's handling.
- **Missed `setVisibility` op** in `/sync` (or the echoed `visibility` field): update `meta.visibility`; if it went private and this device had the list as an editor mirror (not possible for the owner, but editors of the list get 403 → demoted as today).
- **Over the entry cap**: `addEntry` rejected with `list_full` → today's `listFull` notification; the sign stays local-only.

### 5.6 Follows

Subscribe (share link, landing page, paste dialog) → local subscriber mirror as today plus `follow`. Unsubscribe → `unfollow`. Incoming follows → `engine.subscribe`; unavailable ones go in `followsGone` and are retried at most once a day. An orphaned subscriber mirror ("deleted by its owner") stays until unsubscribed on some device, as today. Signed out, subscribing and unsubscribing are local only; signing in merges by union (a list unfollowed while signed out comes back, consistent with decision 5).

### 5.7 Editor lists

Lists the person edits but doesn't own keep today's model: discovered through `editorListIds` (the Worker lists the `editors/` index into the sync response), installed without asking, dropped on sign-out, demoted to subscriber on 403.

### 5.8 Revision

**One writer.** `ReviewHistory` (`lib/revision_history.dart`, global `reviewHistory`) is the only code that reads or writes `KEY_STORED_REVIEWS` and `reviews_unsent`:
- `List<Review> read()`: today's `readReviews`.
- `Future<void> appendLocal(List<Review> answers)`: under its lock, re-read, append, write; if signed in, also append to `reviews_unsent`. Replaces `writeReviews(existing, additional)`, which is deleted. `FlashcardsPage.beforePop` calls this; it no longer receives `existingReviews`.
- `Future<int> mergeRemote(List<Review> incoming)`: under the lock, re-read, add every incoming review whose `(master, combination, ts)` is absent, write, bump `version`; returns how many were new.
- `Future<void> reset(int tsUs)`: under the lock, drop reviews with `ts < tsUs`, write, clear `reviews_unsent`, bump `version`.
- `ValueListenable<int> version` bumped after `mergeRemote` and `reset`. `FlashcardsLandingPage` listens and sets `existingReviews = null` so the next `updateDolphin` re-reads; `RevisionHistoryPage` rebuilds.

The Settings "Delete all revision progress" row calls `reviewHistory.reset(nowUs)`, zeroes the local random counter and enqueues `resetProgress {tsUs}`.

**Receiving.** Each sync page's `reviews` go through `mergeRemote` and `sinceSeq` is saved only after the write returns; a kill between the two re-fetches the same page, which is harmless. `resetTsUs` greater than the last seen value → `reviewHistory.reset(resetTsUs)` before merging that page.

**Sending.** Section 5.2 step 6. Timestamps are device clocks; the reset cut-off compares them across devices, so a device with a badly wrong clock can keep or lose a few answers at a reset boundary. Accepted.

**Random mode.** `bumpRandomReviewCounter` keeps the local counter and, when signed in, enqueues `randomSession {count, tsUs: now}` with a fresh op id. The progress page shows, when signed in, `randomTotal` from the last sync response plus the counts of still-pending `randomSession` ops; signed out, the local counter.

**Settings.** `syncedSettingKeys` in dictionarylib: `KEY_SIGN_TO_WORD`, `KEY_WORD_TO_SIGN`, `KEY_REVISION_STRATEGY`, `KEY_REVISION_CARD_LIMIT`, `KEY_USE_UNKNOWN_REGION_SIGNS`, `KEY_FLASHCARD_REGIONS`, `KEY_REVISION_LANGUAGE_CODE`, `KEY_LISTS_TO_REVIEW`. Writes to these go through `syncedSettings.set(key, value)` (prefs write plus `setSetting`); reads stay plain prefs reads. An incoming value is applied unless a `setSetting` for that key is still pending. `KEY_LISTS_TO_REVIEW` is encoded on the wire as a list of `list:<serverListId>`, `community:<key>` or `local:<localKey>`; when applying, ids are mapped back to this device's keys and unknown ones are dropped, matching today's "a chosen list that isn't found is left out". Values are JSON (`bool`, `int`, `String`, `List<String>`).

### 5.9 Sign-out, account switch, expiry, deletion

- **Sign-out** (`Sharing.signOut`): best-effort flush for 10 s (list queues and the account queue), then clear pending ops, remove every owner and editor wrapper (local lists keep their signs; subscriptions stay), remove `account_sync_state` and `reviews_unsent`, clear the session. The history stays. Copy: "Sign out? Your lists and progress stay on this device but stop syncing. Sign in again on any device to keep going."
- **Another account signs in** on a device that has state for a previous account: `switchAccount()` does what sign-out does locally (without the flush, the old session is gone), then the merge runs for the new account, which uploads whatever is on the device into it. That is decision 5 applied to accounts.
- **Session expired (401)**: as today, drop the session, keep everything, show the resume banner; signing in as the same account resumes; as a different one, `switchAccount`.
- **Account deletion**: server wipe (4.4), then the local steps of sign-out.

### 5.10 Device restore

A restored phone brings `SharedPreferences` and, on iOS, the keychain session, so it starts as a clone of the old phone with the same `KEY_SHARED_CLIENT_ID`.

- **Marker.** On iOS, a keychain item `install_marker` written with `IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device)`, which is not migrated to a new device. On Android, a file `install_marker` in `getApplicationSupportDirectory()`, excluded from backup.
- **Android backup rules.** Add `android/app/src/main/res/xml/backup_rules.xml` (`<full-backup-content>`) and `data_extraction_rules.xml` (API 31+) to both apps, referenced from the manifest's `<application>` as `android:fullBackupContent` and `android:dataExtractionRules`, excluding `file` path `install_marker` and `sharedpref` `FlutterSecureStorage.xml` (the plugin's prefs file; its key never restores, so the session would be unreadable anyway). Flutter's own `FlutterSharedPreferences.xml` stays included so lists survive a new phone for people who don't sign in.
- **Detection**, at startup after prefs load and before `Sharing.setup`: marker present → normal. Marker absent and `KEY_SHARED_CLIENT_ID` present → restored: generate a new client id, write the marker, log it, analytics `restore_detected`. Neither → fresh install: write the marker. Everything else is left as it is: pending list ops are idempotent by op id, pending account ops too, `reviews_unsent` lines dedupe on the server, and `randomSession` ops keep the op ids they were saved with.

### 5.11 UX and copy

- **Settings → Account** (replaces the Sharing section). Signed out: row "Sign in to keep your lists and progress on all your devices" → sign-in dialog. Signed in: "Signed in with {provider}" with a status subtitle: "Syncing…", "Synced just now" / "Synced {n} minutes ago", "Waiting for a connection", "Sync is paused", then "Sign out" and "Delete account". The status comes from the controller (`lastSyncAt`, `pausedUntil`, the last error kind).
- **My lists footer.** Signed out: "Sign in to keep your lists on all your devices." as a tappable line opening the sign-in dialog. Signed in: nothing. The interim `listsSyncHint` line and the edit-hint column go back to the edit hint alone.
- **Sign-in dialog** title: "Sign in to share and sync" (`signInDialogTitle`), wherever it opens from. Default body: "Sign in to keep your lists and progress on all your devices." The share flow's `contextMessage`: "Sharing needs an account. Signing in also keeps your lists and progress in sync across your devices."
- **After the merge**: "Your lists and progress are now syncing."
- **Delete list**: "Delete “{name}” from all your devices?". **Stop sharing** as in 5.5. **Too large**: no snackbar; the list's row on My lists shows the subtitle "Not synced: more than {limit} signs" for as long as that is true.
- **Privacy**: App Store privacy label (the October audit found "Data Not Collected", wrong even today), Play's Data safety form and the privacy policy now cover lists, follows and revision history tied to the account. Account deletion already removes everything and now covers the account DO.
- Strings go in the three arbs; Sinhala and Tamil are machine translations marked for review, as the interim ones were.

### 5.12 Removed

`lib/sharing/account_lists_prompt.dart`, `account_lists_record.dart`, `ListsService.checkAccountLists`, `_oneAtATime`, `importEditableLists`, `_fetchAccountLists`/`_applyAccountLists` (their editor and owner install code moves into the controller), `SyncEngine._changingMembership` and the epoch fields, `offerAccountLists` in Settings, the `accountLists*` and `listsSyncHint` strings, `writeReviews`, the `unshareToDeleteTooltip` rule. None of these exist at `HEAD`; if the interim fix lands on `master` first, the sync branch deletes them on rebase.

### 5.13 App tests

Unit and widget (`flutter test`):
- Merge: default list into an account default; same-name match (case, whitespace, underscores); creation with saved ids resumed after a kill at every step (using `test/_recording_prefs.dart` as `list_storage_sessions_test.dart` does); two lists called Pets; a 5001-sign list marked unsyncable; reorder result; account lists arriving with name collisions.
- Controller: one cycle at a time; kicks coalesce; backoff; kill switch pause; account switch; sign-out clears state; restore detection.
- Lists: delete sends `delete` and removes locally; delete while linking; deleted elsewhere with and without pending ops; 410 → `unlink`; share and stop sharing flip visibility; the default list can't be deleted.
- Follows: subscribe/unsubscribe ops; incoming follow; gone follow retried daily.
- Revision: `appendLocal` during a background `mergeRemote` loses nothing (the bug the single writer exists for); an older answer arriving after a newer one; reset against late answers; `reviews_unsent` drains with deterministic op ids and survives a kill before the ack; random total display; settings LWW and the lists-to-revise mapping.
- Wire: every new request and response parses; unknown fields ignored; `UNAVAILABLE` maps to `unavailable`.
- Availability (Daniel, 2026-10-29): the fake server gets a `NetworkSwitch` (`up`, `down`, `blackhole`, `flaky`, `slow`, `lossy`, the last applying the request but losing the response), and scenario tests use it: first sign-in with the backend down; the backend down after each merge step; a long offline session (saves, renames, reorder, delete, follow, a revision session, a setting) then back online; `lossy` for every op type with nothing doubled; `flaky` with a bounded number of requests over an hour of fake time; `blackhole` with every UI operation completing without the clock advancing; coming back online by each path (resume, the retry timer within five minutes, pull-to-refresh, a local change that waits for the timer); two devices offline on one list in both orders; delete against offline edits in both orders; session expiry found on return; the kill switch on and off; list operations during a black-holed merge. The same scenarios run against the real Worker through an in-test TCP proxy with the same modes, and an on-device suite (`solo_offline_online`) drives the real UI through an in-app proxy that is taken down and brought back.

Multi-device (`dictionarylib_test_support/lib/multi_device/`, stubs in both apps, run by appci's `multi_device_run.sh`):
- `phase_e_two_devices_sign_in`: both devices hold a list called "Animals" with different signs, sign in within seconds of each other; both end with one "Animals" holding the union.
- `phase_f_offline_edits`: both edit the same list offline, come back; union, no duplicates.
- `phase_g_delete_elsewhere`: device A deletes; device B loses it, or keeps it when B had unsent edits.
- `phase_h_revision_both_ways`: a session on each device; each sees the other's answers in its due counts and the progress page.
- `solo_old_build_stop_sharing`: a list shared via the old `POST /v1/lists` path and "deleted" via a header-less `DELETE` is still on the account as private.
- `upgrade_sync_from_old_install`: the old-build-then-new-build routine (`flutter-upgrade-check-on-device` in memory): lists, history and progress figures survive the update and the first sign-in.
- Restore: copy one simulator's app container into a fresh install and check the clone gets a new client id and no double counting.
- Phase C and D are rewritten to sign in and wait for the merge instead of calling `importEditableLists`.

Note for the implementer: appci `main` (e34fbf3) already runs a `solo-follow` suite, `solo_follow_link_test.dart`, that lives on the `share-landing-highlight` branches of dictionarylib and both apps (worktrees `*-share-landing`), not yet on `main`/`master`. Until `account-sync` is rebased onto that work, run the multi-device phases individually rather than through the whole driver, and don't add a stub for that suite.

## 6. Failure matrix

| Event | Outcome |
|---|---|
| Killed between creating a local list and saving `linking` | Next cycle sees a `local` list and links it; the create uses a new request id. |
| Killed after saving `linking` and before the answer | Retry with the same request id and list id: the account DO finds the row (or re-runs the idempotent `init`). No second list. |
| Killed after the wrapper's meta is written and before the index | Meta without an index entry is cleaned up at load as today; the list is `local` again and re-links by name. |
| `createList` answers `id_collision` | New list id and request id, retry. |
| Two devices create "Animals" at once | The account DO serialises them: the second finds the first by name and merges. |
| Two devices rename, reorder, change the default list or a setting while offline | The op with the later (clamped) client timestamp wins on the server; the other device adopts it on its next sync. |
| Device deletes a list while another device edits it | Timestamps decide: edits newer than the delete restore the list everywhere with the edits; edits older than it are dropped and the list goes. Nobody is told. |
| Old build stops sharing a list that a new build also has | Converted to private; the new build sees `visibility` change and drops the badge; nothing is deleted. |
| Old build creates a shared list | Reconciled into the directory on the next account sync of any new device. |
| Account DO unreachable, list DOs fine | Lists keep syncing through the engine; account steps back off. |
| Kill switch on | 503 → one-hour pause, status line "Sync is paused"; lists already linked keep syncing through `/sync`, which is not switched off. |
| Answers arrive while a revision session is open | Merged into storage under the lock; the session's own answers append afterwards; the landing page re-reads on return. |
| Reset on device A while B is offline with old answers queued | B's late answers are refused by the cut-off and dropped locally when B applies the reset. |
| Session expires mid-merge | State kept; merge resumes after the next sign-in as the same account. |
| Different account signs in | Device state is cleared as on sign-out, then merged into the new account. |
| Restored from backup | New client id; every queued op is idempotent; no double counts. |
| List over 5000 signs | Stays local, labelled; the rest sync. |
| Server loses state relative to a device's cursor (`stale_cursor`) | Today's engine recovery (`/state` re-adopt) for lists; for the account, `sinceSeq` greater than the server's `seq` → the device sets `sinceSeq = 0` and re-merges history (duplicates are ignored). |

## 7. Phases

| Phase | Deliverables | Done when |
|---|---|---|
| 1 Backend | List DO schema v3, `init` idempotency, reserved-name split, `addEntries`, `setVisibility`, soft delete, purge alarm, `restore`, `purge`; account DO and every op; routes; legacy `DELETE`; kill switch; error codes; limits; `CURL_GUIDE.md` and `RUNBOOK.md` updated; backup and restore scripts | `bun run typecheck`, `bun test` and `bun run test:integration` against `wrangler dev` pass with the tests in 4.7; today's Dart client (`flutter test` in dictionarylib at `HEAD`, including `multi_device_sync_test.dart` against the new Worker) still passes untouched. |
| 2 Lists | Controller, link states, merge, steady-state list ops, follows, editor lists, sign-out and switch, restore handling and backup rules, Settings and footer, copy and translations, the knob, analytics events, removals | `flutter analyze` clean, `flutter test` green, the multi-device phases A to G and the three solo suites pass on two simulators against `wrangler dev`, the upgrade check passes. |
| 3 Revision | `ReviewHistory`, `reviews_unsent`, upload and download, reset, random sessions, settings | Tests in 5.13's revision list, phase H, and a run of the existing single-device revision suites. |
| 4 Recently deleted | A screen under Settings listing `deleted` directory rows with a Restore button (`restore` op) | Optional; after 1 to 3 ship. |

Phases 1 to 3 are the feature. Ship the backend first: it serves old and new clients alike. The app ships behind the knob: internal builds, beta, then the stores.

## 8. Rollout

- `enable_account_sync` knob files are created in each app's knob directory before the app build ships, reading `true`; the hard-coded fallback is also `true`, so the knob can only turn the feature off.
- Analytics (bucketed like the others, no ids): `sync_merge_completed {lists_bucket, answers_bucket}`, `sync_failed {kind}`, `sync_list_unsyncable {reason}`, `restore_detected`.
- Watch `sync_failed` and the Worker's logs after each stage; the kill switch and the knob are the brakes.
- Before the store release: the PITR rehearsal on `--env dev`, a backup run that includes account DOs, and the privacy label, Data safety form and privacy policy updates.

## 9. Rules for building this

- Build on a branch named `account-sync` in each repo touched (dictionarylib, dictionary_backend, auslan_dictionary, slsl_dictionary, appci), each in its own git worktree beside the main checkout (`git worktree add ../<repo>-account-sync -b account-sync`), so the main checkouts and their uncommitted work are untouched. Point the apps at the dictionarylib worktree with the gitignored `pubspec_overrides.yaml`.
- Commit locally on those branches as each phase lands; the pre-commit hooks will bump versions, which is fine. Do not push, repin, deploy, upload or promote anything. Daniel publishes.
- Run before each commit: dictionarylib `flutter analyze` and `flutter test`; workers `bun run typecheck`, `bun test`, and `bun run test:integration` with `bunx wrangler dev --env dev --port 8787` running (delete `workers/.wrangler/state/v3` for a fresh backend). Run the multi-device suites when two simulators are available; say plainly which runs happened and which didn't.
- Markdown edits: never break a sentence or paragraph across lines.
- Keep the prose style of the surrounding code and comments.

## 10. Deferred: dropping flashcard history from the device

Not planned for now (Daniel, 2026-10-28: no compaction anywhere, for simplicity). Recorded so it can be picked up later.

Everything the app does with the history today comes down to two jobs:

1. **Rebuilding each card's schedule.** At the start of every revision session the app replays every answer the person has ever given, sorted by time, to work out what is due. The result is a small state per card (about 160 KB for someone who has studied 2,000 cards), so the app could save that instead and stop replaying.
2. **The Revision progress page.** It shows total answers, remembered, forgotten, signs seen and the longest streak. The first four are counters. The streak needs the dates someone revised on, not every answer.

So day to day the device needs no history at all. History is still worth keeping somewhere, for three reasons:

- **Merging two devices' answers to the same card,** when the older one arrives second. With only card states, the device would fetch that card's answers from the server and replay them.
- **Recomputing every schedule if the scheduling maths changes:** a dolphinsr bug fix, or moving to a better algorithm. Without history, every schedule built by the old maths stays as it is.
- **Recovery:** if saved card states were ever lost or damaged, history rebuilds them.

The shape it would take: the server keeps every answer (it does under this plan); the device keeps card states, the progress figures (with the server keeping the same figures per account) and a queue of unconfirmed answers; a signed-out device appends its answers to an archive file it never reads in normal use, uploaded and trimmed once the person signs in.

What it would take and change:

- **The history leaves SharedPreferences,** where today it is one entry loaded into memory at every start and rewritten in full after every session. The archive is about 1 MB a year for someone revising 50 cards a day.
- **A dolphinsr release** that can export and import card state. It keeps the state internally but has no way to seed it.
- **A one-time migration** on first launch: replay the history once, save the card states and figures, move the answers to the archive, with crash-point tests.
- **The streak would change meaning slightly.** Today two sessions count as consecutive when they are up to about 36 hours apart; from a set of dates, a streak becomes consecutive calendar days in the person's time zone. The rules disagree only around midnight. Revising at 11 pm on Monday and then at half past midnight on Wednesday keeps a streak today but breaks it by calendar days. Revising at half past midnight on Monday and then at 11 pm on Tuesday breaks it today but keeps it by calendar days.

## 11. Decided

1. Merge silently when signing in (2026-10-28).
2. No off switch: signing in is syncing (2026-10-28).
3. Followed lists sync (2026-10-28).
4. No compaction anywhere for now; the device keeps its full flashcard history (2026-10-28).
5. From the review (2026-10-28): an old build's `DELETE` becomes "make private" once the owner has an account; private lists stay out of the `owners/` index instead of gating `my-lists`; a private list may be called Favourites; `addEntries` only on private lists; random totals as events; account deletion purges; no first-launch nudge.
6. Daniel, 2026-10-29: nothing waits for the network (renames become a queued op), conflicts are resolved silently with timestamps where the later intent is well defined, and the sign-in dialog is titled "Sign in to share and sync".

Open questions for Daniel: none.
