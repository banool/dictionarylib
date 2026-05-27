import 'dart:math';

/// Strict alphabet for **generating** new list IDs — RFC 4648 base32
/// (a-z + 2-7), 12 chars = 60 bits of entropy. Comfortably collision-
/// resistant at millions of lists and ~unguessable, which doubles as
/// access control for subscribers (the share URL is the only thing
/// they need to read a list).
///
/// The R2 object key is also derived from the list id, so we keep the
/// character set conservative.
const String _listIdAlphabet = 'abcdefghijklmnopqrstuvwxyz234567';
const int _listIdLength = 12;

/// Loose pattern for **validating** an incoming list id (from a pasted
/// URL or freeform input) — accepts any lowercase alphanumeric of up
/// to 64 chars. Deliberately wider than [_listIdAlphabet] so that
/// future generators can pick different alphabets / lengths without a
/// client-side parser change. The Worker's `LIST_ID_RE` in
/// `lists/workers/src/validation.ts` must stay in sync with this.
final RegExp _listIdPattern = RegExp(r'^[a-z0-9]{1,64}$');

/// Maximum acceptable id length. Matches the Worker.
const int maxListIdLength = 64;

/// Generate a fresh random list ID using the strict alphabet.
String generateListId() {
  final random = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < _listIdLength; i++) {
    buf.write(_listIdAlphabet[random.nextInt(_listIdAlphabet.length)]);
  }
  return buf.toString();
}

/// Cheap client-side check that a string looks like a list ID — used
/// when parsing share URLs or freeform input. Matches the loose
/// validator pattern, not the strict generator alphabet.
bool isPlausibleListId(String s) => _listIdPattern.hasMatch(s);

/// A 12-char example id that's both syntactically valid and producible
/// by [generateListId] — used in UI hints so the example matches what
/// real generated ids look like. (Pure 2-7 + a-z, no 0/1/8/9.)
const String exampleListId = 'abcdef234567';
