import 'dart:typed_data';

/// A binary attached to an [Entry]. In KDBX, binary payloads are pooled at the
/// database level and entries reference them by id; large payloads should be
/// streamed rather than held fully in memory (see R4 large-DB handling).
class Attachment {
  Attachment({
    required this.id,
    required this.name,
    required this.size,
    this.inlineData,
  });

  /// Pool reference id (stable within a database).
  final String id;

  /// Display file name.
  final String name;

  /// Size in bytes (known even when [inlineData] is lazily loaded).
  final int size;

  /// Eagerly-loaded bytes, or null when the payload is streamed on demand.
  final Uint8List? inlineData;
}
