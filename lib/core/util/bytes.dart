import 'dart:typed_data';

/// Length-then-content byte equality.
///
/// NOT constant-time — use only for comparing NON-secret values (format/cipher
/// UUIDs, content-addressing hashes, public integrity tags). For comparing
/// secrets or MACs against attacker-controlled input, use the constant-time
/// `_constEq` helpers in the crypto layer instead, to avoid a timing oracle.
bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
