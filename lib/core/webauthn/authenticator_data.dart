// dgvault — WebAuthn authenticator data parsing (§6.1).
//
// Layout: rpIdHash[32] ‖ flags[1] ‖ signCount[4 BE] ‖ optional attested
// credential data (when the AT flag is set) ‖ optional extensions (ED flag).
// Attested credential data: aaguid[16] ‖ credIdLen[2 BE] ‖ credId ‖
// credentialPublicKey (COSE CBOR).

import 'dart:typed_data';

import 'cbor.dart';
import 'cose_key.dart';

class AuthenticatorDataException implements Exception {
  AuthenticatorDataException(this.message);
  final String message;
  @override
  String toString() => 'AuthenticatorDataException: $message';
}

class AttestedCredentialData {
  AttestedCredentialData({
    required this.aaguid,
    required this.credentialId,
    required this.credentialPublicKey,
  });

  final Uint8List aaguid;
  final Uint8List credentialId;
  final CredentialPublicKey credentialPublicKey;
}

class AuthenticatorData {
  AuthenticatorData({
    required this.rpIdHash,
    required this.flags,
    required this.signCount,
    required this.raw,
    this.attestedCredentialData,
  });

  final Uint8List rpIdHash;
  final int flags;
  final int signCount;

  /// The exact bytes parsed — these are what the assertion signature covers.
  final Uint8List raw;

  final AttestedCredentialData? attestedCredentialData;

  static const int _flagUp = 0x01; // user present
  static const int _flagUv = 0x04; // user verified
  static const int _flagAt = 0x40; // attested credential data present
  static const int _flagEd = 0x80; // extension data present

  bool get userPresent => flags & _flagUp != 0;
  bool get userVerified => flags & _flagUv != 0;
  bool get hasAttestedCredentialData => flags & _flagAt != 0;
  bool get hasExtensions => flags & _flagEd != 0;

  static AuthenticatorData parse(Uint8List data) {
    if (data.length < 37) {
      throw AuthenticatorDataException('authenticator data too short');
    }
    final rpIdHash = Uint8List.sublistView(data, 0, 32);
    final flags = data[32];
    final signCount = ByteData.sublistView(data, 33, 37).getUint32(0, Endian.big);

    AttestedCredentialData? acd;
    if (flags & _flagAt != 0) {
      if (data.length < 55) {
        throw AuthenticatorDataException('attested credential data truncated');
      }
      final aaguid = Uint8List.sublistView(data, 37, 53);
      final credLen = ByteData.sublistView(data, 53, 55).getUint16(0, Endian.big);
      final credIdEnd = 55 + credLen;
      if (data.length < credIdEnd) {
        throw AuthenticatorDataException('credential id truncated');
      }
      final credentialId = Uint8List.sublistView(data, 55, credIdEnd);

      // The COSE public key follows; use the CBOR reader's offset to find its end.
      final reader = CborReader(Uint8List.sublistView(data, credIdEnd));
      final cose = reader.readItem();
      if (cose is! Map) {
        throw AuthenticatorDataException('credential public key is not a COSE map');
      }
      acd = AttestedCredentialData(
        aaguid: aaguid,
        credentialId: credentialId,
        credentialPublicKey: CredentialPublicKey.fromCose(cose),
      );
    }

    return AuthenticatorData(
      rpIdHash: rpIdHash,
      flags: flags,
      signCount: signCount,
      raw: data,
      attestedCredentialData: acd,
    );
  }
}
