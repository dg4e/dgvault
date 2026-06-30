/// dgvault core — pure-Dart, platform-agnostic domain model and crypto
/// contracts. No Flutter or platform imports may appear under `lib/core/`.
library dgvault.core;

export 'model/protected_value.dart';
export 'model/field.dart';
export 'model/attachment.dart';
export 'model/entry.dart';
export 'model/group.dart';
export 'model/kdf_params.dart';
export 'model/database.dart';

export 'crypto/secure_key.dart';
export 'crypto/key_derivation.dart';
export 'crypto/cipher.dart';
export 'crypto/key_file.dart';

export 'security/app_lock_policy.dart';
export 'security/auto_lock_policy.dart';
export 'security/duress_policy.dart';
export 'security/master_password_reminder.dart';
export 'security/secure_store.dart';
export 'security/key_vault.dart';
export 'security/pin_unlock.dart';
export 'security/challenge_response.dart';

export 'webauthn/cbor.dart';
export 'webauthn/cose_key.dart';
export 'webauthn/authenticator_data.dart';
export 'webauthn/webauthn.dart';

export 'otp/totp.dart';

export 'template/placeholder_resolver.dart';
export 'url/custom_url.dart';

export 'history/entry_history.dart';

export 'search/entry_search.dart';

export 'sort/entry_sort.dart';

export 'format/keepass_xml.dart';
export 'format/variant_dictionary.dart';
export 'format/kdbx_header.dart';
export 'format/kdbx_inner.dart';
export 'format/kdbx_file.dart';
