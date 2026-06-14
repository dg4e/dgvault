import 'attachment.dart';
import 'group.dart';
import 'kdf_params.dart';

/// Cipher used for the outer database encryption.
enum DatabaseCipher { aes256, chacha20 }

/// Metadata describing a database (KDBX meta block).
class DatabaseMeta {
  DatabaseMeta({
    required this.name,
    this.description,
    this.generator = 'dgvault',
    this.recycleBinEnabled = true,
    Map<String, String>? customData,
  }) : customData = customData ?? <String, String>{};

  String name;
  String? description;
  String generator;
  bool recycleBinEnabled;

  /// Arbitrary plugin/app key-values stored in the database (e.g. read-only hint).
  final Map<String, String> customData;
}

/// In-memory representation of a decrypted KeePass database.
///
/// Persistence (read/write KDBX), encryption, and KDF are provided through the
/// crypto contracts; this model is pure data so it can be unit-tested headless.
class Database {
  Database({
    required this.meta,
    required this.root,
    KdfParams? kdf,
    this.cipher = DatabaseCipher.aes256,
    List<Attachment>? binaryPool,
    this.readOnly = false,
  })  : kdf = kdf ?? KdfParams.argon2idDefault(),
        binaryPool = binaryPool ?? <Attachment>[];

  final DatabaseMeta meta;

  /// Root group of the entry/group tree.
  final Group root;

  /// Active key-derivation parameters.
  KdfParams kdf;

  DatabaseCipher cipher;

  /// Database-level binary pool referenced by entry attachments.
  final List<Attachment> binaryPool;

  /// Read-only mode: opened for viewing; writes must be rejected by repositories.
  bool readOnly;

  int get entryCount => root.allEntries.length;
}
