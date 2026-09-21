import 'dart:math';

/// A random (version 4) UUID, formatted canonically.
///
/// Ids are minted on the phone, not by the server, because a record created in
/// airplane mode needs an identity the moment it exists — the farmer can open
/// it, edit it and delete it long before anything reaches a backend. The
/// server's columns are `Uuid`, so these strings insert unchanged.
///
/// Written by hand rather than pulled in as a dependency: this is thirty lines
/// against a specification that has not changed since 2005, and the app's
/// dependency list is something a reviewer has to read.
String newUuid([Random? random]) {
  final rng = random ?? _entropy;
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // RFC 4122 §4.4: version 4 in the high nibble of byte 6, variant 10x in the
  // two high bits of byte 8.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final Random _entropy = Random.secure();
