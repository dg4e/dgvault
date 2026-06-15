// dgvault — KDF dispatch: pick Argon2 or AES-KDF by the header's algorithm.
//
// A KDBX file declares its KDF in the header VariantDictionary; the body cipher
// must run whichever one the file uses. This delegates to [Argon2KeyDerivation]
// (argon2d/id, the default for new DBs) or [AesKdfKeyDerivation] (legacy reads).

import 'dart:typed_data';

import '../../model/kdf_params.dart';
import '../key_derivation.dart';
import '../secure_key.dart';
import 'aes_kdf.dart';
import 'argon2_kdf.dart';

class DefaultKeyDerivation implements KeyDerivation {
  const DefaultKeyDerivation();

  static const Argon2KeyDerivation _argon2 = Argon2KeyDerivation();
  static const AesKdfKeyDerivation _aes = AesKdfKeyDerivation();

  @override
  bool supports(KdfAlgorithm algorithm) =>
      _argon2.supports(algorithm) || _aes.supports(algorithm);

  @override
  Future<SecureKey> deriveKey(
    CompositeCredential credential,
    KdfParams params,
    Uint8List salt,
  ) {
    final kdf = params.algorithm == KdfAlgorithm.aesKdf ? _aes : _argon2;
    return kdf.deriveKey(credential, params, salt);
  }
}
