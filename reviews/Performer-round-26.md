# Performer — Round 26 (platform wiring + app host)

Closing the loop on the R25 cores: the device/network adapters and the native
app host. The honest line from R24 holds — *writing* the wiring doesn't need a
device, *runtime verification* does — and this round proves the wiring at least
**compiles into a real app**.

## Device adapters — `lib/platform/`
- `storage/flutter_secure_store.dart` — `FlutterSecureStorageStore implements
  SecureStore` (Keychain/Keystore/libsecret/DPAPI; bytes base64-wrapped).
- `auth/biometric_gate.dart` — `BiometricGate` over `local_auth` (Face ID / Touch
  ID / fingerprint), gating release of the KeyVault-wrapped key.
- `sync/webdav_remote_storage.dart` — `WebDavRemoteStorage implements
  RemoteStorage` (Nextcloud / generic WebDAV) over `package:http`.

The first two are device-gated (method channels throw off-device), so they are
**analyze-clean but not unit-tested**. The WebDAV adapter **is** tested — driven
by `http`'s `MockClient` (`webdav_remote_storage_test.dart`): HEAD/PUT/GET
mapping, Basic-auth header, error surfacing. No network needed.

## Native app host — scaffolded
`flutter create` added the host projects (`android/ios/macos/linux/windows`) so
the plugins + adapters have a home. Replaced the default counter sample with a
minimal real entrypoint (`lib/main.dart` + a widget smoke test). Native wiring the
adapters require:
- iOS/macOS `Info.plist`: `NSFaceIDUsageDescription` (local_auth crashes without it).
- macOS entitlements: `com.apple.security.network.client` (sandbox blocks sync otherwise).

## Proof it compiles end-to-end
`flutter build macos --debug` → **`✓ Built …/dgvault.app`** — the whole stack
(pure core/data + platform adapters + plugins + native host) links into a real
macOS binary. (Required installing CocoaPods; the Dart side compiled before that,
the pods step links the native plugin code.)

## Build
`flutter test`: **482 passing / 0 failing.** `flutter analyze`: **0 issues.**
`flutter build macos`: **succeeds.**

## What still genuinely needs a device / CI / accounts (not done)
- **Runtime** verification of Face ID prompts, Keychain persistence across
  reboots, and live sync against a real server — needs a device + interaction.
- **Native extensions** with no Dart core: AutoFill (iOS/Android credential
  provider), iOS Files provider, SSH agent — these are Swift/Kotlin targets in the
  now-existing host projects, still to be written.
- **Concrete cloud adapters** with OAuth (OneDrive/Drive/Dropbox/iCloud) — the
  `RemoteStorage` slot is ready; the OAuth dance is account-gated.
- **Secure-Enclave passkey signer** (the private-key side of WebAuthn).
- **YubiKey USB/NFC transport** implementing `ChallengeResponse`.

The repo is now a buildable app, not just a package; every remaining item is a
concrete adapter behind an existing, tested interface.
