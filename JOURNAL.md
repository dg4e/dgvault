# dgvault — Engineering Journal

A comprehensive walkthrough of what dgvault is, how it is built, the reasoning
behind the major decisions, the things you have to be careful about, and a
step-by-step deployment guide for every supported platform.

This document is a companion to `README.md` (quick start) and the ADRs in
`docs/`. Where the README tells you *how to run it*, this journal explains
*why it is the way it is*.

---

## 1. What dgvault is

dgvault is a **cross-platform, KeePass-compatible password manager** written in
a single Flutter/Dart codebase. It reads and writes real **KDBX 3 / KDBX 4**
databases, so it interoperates with KeePass, KeePassXC, KeePassDX, Strongbox,
and every other tool in that ecosystem — your vault is not locked into dgvault.

Design pillars:

- **Zero-knowledge, local-first.** The vault is encrypted on the device with
  vetted crypto (Argon2 / AES-256 / ChaCha20). There is no server, no account,
  no telemetry. dgvault never phones home.
- **One codebase, five platforms.** macOS, Windows, Linux, iOS, and Android —
  plus the web target as a stretch surface — from the same Dart source.
- **A hacker / terminal aesthetic** that scales from a phone to a desktop:
  monospace type, box-drawing panels, an Amiga-style "cracktro" About screen,
  and randomized *Hackers* (1995) quotes on the landing banner.

Current version: **0.8.2** (see `pubspec.yaml`; the version is surfaced
automatically in the UI and desktop title bar via `package_info_plus`, never
hardcoded in the UI). Bundle / application id: `com.dgvault.dgvault`.

---

## 2. Technology stack and why each piece was chosen

| Concern | Choice | Reasoning |
|---|---|---|
| UI + app framework | **Flutter / Dart** | One rendering pipeline and one language across desktop + mobile. The custom terminal aesthetic is drawn by Flutter itself, so it looks identical everywhere instead of fighting five native widget toolkits. |
| Crypto primitives | **pointycastle** + **cryptography** | Vetted, widely-used implementations of Argon2, AES, and ChaCha20. **We hand-roll no crypto.** Every KDF/cipher is delegated to a reviewed library. |
| KDBX reference | **kdbx** package | Reference for the KDBX 4.x container semantics; dgvault has its own layered reader/writer (`lib/core/format`, `lib/core/crypto`) so the format handling is testable headless and hardened against malicious files. |
| OS secret storage | **flutter_secure_storage** | Wraps the platform keystore (Keychain / Keystore / libsecret / DPAPI) for derived-key material — the right place for OS-guarded secrets. |
| Biometrics | **local_auth** | Face ID / Touch ID / fingerprint / device-credential gate, per-platform, behind one API. |
| File pickers | **file_picker** | Native open/save dialogs on desktop and mobile. (Mobile in-place save uses platform channels on top of this — see §5.) |
| Desktop window | **window_manager** | Lets us put `dgvault vX.Y.Z — <file>` in the real OS title bar and manage the desktop window. |
| App metadata | **package_info_plus** | Reads the real build version at runtime so the UI is never out of sync with `pubspec.yaml`. |
| Paths | **path_provider** | App-documents / support directories for managed vaults and scratch files. |
| Networking | **http** | Thin client for optional sync adapters (WebDAV). Fail-closed, HTTPS-only. |
| XML | **xml** | KDBX inner payload is XML; used by the KeePass XML reader/writer. |
| Fonts | **JetBrains Mono (OFL), bundled** | The terminal glyphs (box-drawing, arrows, ⌘) must render identically everywhere. A bundled font avoids system-font fallback rendering them as `?`. |
| Lints | **flutter_lints** + `require_trailing_commas` | Enforced; `flutter analyze` must be clean before every commit. |

Environment the project was developed against: **Flutter 3.44.x**, Dart SDK
`>=3.3.0 <4.0.0`, **JDK 17** for Android (Gradle 9 / AGP reject newer JDKs),
Android **platform 36 / build-tools 36.0.0**, Xcode for iOS/macOS.

---

## 3. Architecture

The codebase is deliberately **layered so the security core stays pure and can
be tested headless** (no Flutter, no `dart:io`, no device):

```
lib/
├── core/        Pure Dart. No dart:io, no Flutter. The security-critical heart.
│   ├── crypto/      KDFs (Argon2, AES-KDF), ciphers (AES-256, ChaCha20), composite key
│   ├── format/      KDBX header/inner, VariantDictionary, KeePass XML
│   ├── model/       Database, Group, Entry, Field, ProtectedValue, KdfParams
│   ├── security/    auto-lock, app-lock, clipboard auto-clear, PIN, duress, key vault
│   ├── generator/   charset + diceware password generation
│   ├── otp/         TOTP
│   ├── search/ sort/ diff/ history/ audit/ tags/ …  (feature logic, all pure)
│   └── webauthn/    CBOR, COSE keys, authenticator data (bounds-checked parsers)
│
├── data/        dart:io-backed. Repositories, sync engine, import/export, gzip.
│
├── platform/    Device adapters. Biometric gate, secure store, WebDAV storage.
│
└── ui/          Flutter. Terminal theme, screens, widgets, and the app "controller".
    ├── state/       VaultController (ChangeNotifier), file_service, documents bridge
    ├── screens/     landing, unlock, vault, entry editor/detail, generator, cracktro
    ├── widgets/     folder tree, banner logo, auto-lock gate, terminal widgets
    └── theme/        TermColors, mono(), platform/breakpoint helpers
```

Why this shape:

- **`core/` is pure** → the crypto and format code runs in plain `dart test`
  with no device, so security logic is exhaustively unit-tested (79 test files).
- **`data/` isolates `dart:io`** → file/network side effects are in one place.
- **`platform/` isolates the device** → biometrics, keystore, and sync each have
  a swappable adapter, which keeps the rest of the app deterministic.
- **`ui/` owns Flutter only** → the state hub is a single `VaultController`
  (`ChangeNotifier`); screens rebuild via `ListenableBuilder`. No heavyweight
  state-management dependency; the app's state is small and explicit.

Rationale is recorded in `docs/ADR-0001-stack-and-architecture.md` and
`docs/ADR-0002-zero-knowledge-model.md`.

### Entry point and launch flow

`lib/main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `loadAppInfo()` — populate the real version **before** the first frame.
3. `initDesktopWindow()` — set the desktop title bar (no-op on mobile/web).
4. `runApp(DgvaultApp(initialFile: …))` — Windows/Linux/macOS pass a launched
   `.kdbx` as a command-line argument; iOS/Android deliver it over a
   MethodChannel (see §6).

---

## 4. The KDBX / crypto core

- **Formats:** KDBX 3 (read; a save upgrades it to KDBX 4) and KDBX 4
  (read/write). dgvault always *writes* KDBX 4.
- **KDF:** Argon2id by default (via a KDF registry), with AES-KDF supported for
  legacy files. Transform rounds are user-tunable in Settings with a
  **Benchmark** button so users can pick a work factor matched to their device.
- **Ciphers:** AES-256 and ChaCha20 for the database body; a fresh
  seed / IV / salt is generated on **every** save.
- **Composite key:** password (and optionally a key file / challenge-response)
  combined per the KeePass spec.
- **Secret hygiene:** secrets are zeroized (`_wipeSecrets()`) on lock, close, and
  dispose. Key material is held as bytes and wiped, not left for the GC.

### Parser hardening (things to be careful of)

KDBX files are **untrusted input** — a vault can arrive by email, download, or a
malicious file-association open. Every pre-authentication parser is bounds- and
resource-checked so a hostile file cannot crash or exhaust the app **before** the
password is even entered:

- Bounded TLV loops in the header / KDBX3 readers and the `VariantDictionary`.
- A recursion cap in the CBOR decoder (WebAuthn path).
- A **256 MiB decompression-bomb cap** in the gzip layer (`GzipException`).
- Base64 guards in the key-file and KeePass-XML readers.
- Integer-encoding / local-net guards in the network-import path (fail-closed).

These are covered by `test/…/parser_hardening_test.dart` and friends. If you
touch a parser, keep the bound — "trust the file" is never acceptable here.

---

## 5. In-place save on mobile (the tricky part)

Desktop is easy: you have a real filesystem path and you write to it. Mobile is
not — both Android and iOS sandbox file access, and the naïve approach (import a
copy into app-private storage) means **edits don't land on the user's actual
file**. dgvault does true **in-place save-back** on both mobile platforms, unified
behind one Dart abstraction.

### The unifying idea

`lib/ui/state/documents.dart` defines a `Documents` bridge over a single
`MethodChannel('dgvault/documents')`. The vault's "path" is an **opaque location
token**; `VaultController._writeLocation()` routes on it:

```dart
Future<void> _writeLocation(String location, Uint8List bytes) async {
  if (Documents.isDocumentUri(location)) {
    await Documents.write(location, bytes);   // native, in place
  } else {
    await File(location).writeAsBytes(bytes, flush: true);  // desktop filesystem
  }
}
```

`isDocumentUri` recognizes two token shapes:

- **Android** — a SAF `content://` URI.
- **iOS** — a security-scoped bookmark, encoded `bookmark:<base64>`.

### Android — Storage Access Framework

`android/.../MainActivity.kt` runs `ACTION_OPEN_DOCUMENT` /
`ACTION_CREATE_DOCUMENT`, calls `takePersistableUriPermission(READ|WRITE)`, and
reads/writes via the content resolver (`openOutputStream(uri, "wt")` — write +
truncate, full replace). Because the grant is *persistable*, later saves write
straight back to the file the user chose.

### iOS — security-scoped bookmarks

`ios/Runner/DocumentPickerBridge.swift` runs `UIDocumentPickerViewController`:

- **Open** (`.open` mode) → a security-scoped URL; we hand Dart
  `bookmark:<base64>` (the bookmark *is* the token — stateless, needs no native
  registry, and resolves across app launches).
- **New** → write an empty placeholder to a temp file, `.moveToService` moves it
  to the user's chosen location; Dart immediately overwrites it with the real
  encrypted vault, so the empty file never persists.
- **read/write** → resolve the bookmark, `start/stopAccessingSecurityScopedResource`,
  and use **`NSFileCoordinator`** so reads/writes are safe across iCloud and
  third-party document providers.

The bridge is retained by `AppDelegate` and registered on the same messenger as
the open-file channel.

### The platform matrix

| Platform | Open/New | Save target | Mechanism |
|---|---|---|---|
| Desktop (macOS/Win/Linux) | native picker | the real path, in place | `dart:io` |
| Android | SAF picker | the picked `content://`, in place | persistable URI permission |
| iOS | Files picker | the picked file, in place | security-scoped bookmark |

**Things to be careful of:**

- iOS deployment target is **13.0**, so the bridge uses the
  `documentTypes:in:` / `url:in:` picker initializers (deprecated but functional
  on iOS 14+). Migrating to the `UTType`-based iOS 14 APIs is a clean-up option
  but would drop 13.0 support unless branched.
- Android VIEW-intent opens (tap a `.kdbx` in a file manager) grant **read-only**
  access, so those open read-only; the explicit SAF picker is what grants write.
- iOS bookmarks from *opened-in-place* documents are valid for the session; the
  code **falls back to a managed copy** if no in-place grant is available, so it
  degrades gracefully rather than failing to save.

### Verification note

The Android round-trip is verified on-device (create in Downloads → add an entry
→ Save → the file grew `789 → 933` bytes, mtime updated, KDBX magic intact). The
iOS path is verified by build + unit tests + live launch; the Files
document-picker is a separate system UI that **cannot be scripted on the
simulator in a sandbox without accessibility/idb**, so that final tap-through is
a manual check.

---

## 6. `.kdbx` file association (open a vault from the OS)

Tapping a `.kdbx` in Finder / Files / a file manager launches dgvault straight to
the unlock screen. This is wired per platform and normalized in
`lib/ui/state/open_file_channel.dart`:

- **macOS / iOS** — `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`
  (`org.keepass.kdbx`), `LSSupportsOpeningDocumentsInPlace`. The native runner
  reads the bytes and delivers `{name, bytes, path?}` over the
  `dgvault/open_file` channel (cold start via `getInitialFile`, warm start via a
  pushed `openFile` call). iOS attaches a bookmark so opened files save in place.
- **Android** — an intent-filter for `.kdbx`; the VIEW intent's bytes are read
  and delivered over the same channel.
- **Windows / Linux** — the launched path arrives as a **command-line argument**
  (`dgvault path.kdbx`); `main.dart` picks the first existing `.kdbx` arg.
  Install-time file association is the packager's responsibility.

Bytes (not just a path) are passed so Android `content://` URIs and iOS
security-scoped URLs work uniformly.

---

## 7. Security model — things to be considerate of

- **Zero-knowledge / local-first.** No account, no server, no telemetry. The
  master password never leaves the device; there is no recovery path — this is a
  deliberate property, not a gap.
- **Auto-lock.** Two independent policies (pure, clock-injectable —
  `lib/core/security/auto_lock_policy.dart`): lock after *X* minutes idle, and
  lock after *Y* minutes when focus is lost (e.g. switching apps on mobile). The
  `AutoLockGate` widget drives them from pointer activity + app-lifecycle events.
- **Clipboard auto-clear.** Copied secrets are cleared on a generation-guarded
  timer (a newer copy supersedes an older clear). Platform callers should verify
  the clipboard still holds the secret before wiping, to avoid clobbering
  externally-copied content.
- **Secret zeroization.** Keys and plaintext are wiped on lock/close/dispose.
- **Untrusted input.** See §4 — every pre-auth parser is bounded. Keep it that way.
- **Sync credentials.** WebDAV is **HTTPS-only** and cross-origin-checked;
  network import is **fail-closed** and rejects local-net / integer-encoded IPs.
  Credentials are never sent over plaintext HTTP.
- **Web-style classes (XSS/SQLi/CSRF/IDOR/session)** are **not applicable** —
  dgvault is a local app with no server, no web view for untrusted content, and
  no multi-user authz surface. The relevant threat model is *malicious files* and
  *local device compromise*, which is what the hardening above targets.
- **Save reentrancy.** `save()` guards against reentrancy and tracks a mutation
  sequence so an edit landing mid-save keeps the vault dirty (re-saved) rather
  than being silently marked clean.

The full audit trail lives in `reviews/` (multi-round adversarial reviews) and
`docs/ADR-0002-zero-knowledge-model.md`.

---

## 8. Testing & quality gates

```bash
flutter analyze    # must be clean (lints incl. require_trailing_commas)
flutter test       # full unit + widget suite (573+ tests across 79 files)
```

- The **pure `core/`** is tested headless — crypto round-trips, parser
  hardening, generators, search/sort/diff, auto-lock policies.
- **Widget tests** cover the UI: responsive header, hotkey hints hidden on
  mobile, drag-to-reorder, tooltips, copy-to-clipboard, folder tree.
- **Platform-sensitive tests** pin `debugDefaultTargetPlatformOverride` and
  reset it **within the test body via try/finally** (not `addTearDown`, which
  trips a foundation invariant).

Conventions worth keeping: `flutter analyze` clean and the full suite green
before every commit; new behavior ships with a test.

---

## 9. Step-by-step deployment

> Prerequisite for all targets: `flutter pub get`, and a green `flutter doctor`
> for the platforms you build. Confirm the version in `pubspec.yaml`
> (`version: X.Y.Z+build`) — it flows automatically into the UI and title bar.

### 9.0 App icons (once per icon change)

```bash
python3 tool/gen_icon.py    # regenerates macOS/iOS/Android/Windows/Linux icons
```

### 9.1 macOS

```bash
flutter build macos --release
# → build/macos/Build/Products/Release/dgvault.app
```

Distribution:
- **Direct / notarized:** sign with a Developer ID cert, `xcrun notarytool
  submit`, staple, then ship a `.dmg`/`.zip`.
- **Mac App Store:** open `macos/Runner.xcworkspace` in Xcode, set the team /
  provisioning, Archive → Distribute.

Considerations: entitlements/sandbox live in `macos/Runner/*.entitlements`; the
title bar and About menu (which triggers the cracktro) are wired via
`window_manager` + `PlatformMenuBar`.

### 9.2 iOS

```bash
flutter build ios --release        # needs a signing team
# then Archive for distribution:
open ios/Runner.xcworkspace        # Xcode → Product → Archive → Distribute App
```

**Deploy to a physical device.** With `DEVELOPMENT_TEAM` set (it is, in the
Runner build configs), `flutter run --release -d <device-id>` builds and signs.
On recent iOS (**26.x**) the tooling may finish the signed build but then fail at
"Installing and launching…" — this is a `flutter`/`ios-deploy` gap, not a signing
problem. Install the already-built `.app` directly with Apple's `devicectl`:

```bash
flutter build ios --release
DEV=$(xcrun devicectl list devices | grep -i iphone | awk '{print $3}' | head -1)
xcrun devicectl device install app --device "$DEV" build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device "$DEV" com.dgvault.dgvault
```

Considerations:
- Set the **signing team** (Runner target → Signing & Capabilities → your Team)
  and, for store builds, a distribution profile (bundle id `com.dgvault.dgvault`).
- Deployment target is **iOS 13.0**.
- First cold launch may need **Settings → General → VPN & Device Management →**
  trust your developer cert.
- The `.kdbx` document type and in-place save (§5–6) are already declared in
  `Info.plist`; no extra config for TestFlight / App Store.
- The document-picker save-back is best verified on a **real device** (or
  manually on a simulator), since it can't be scripted headlessly.

### 9.3 Android

One-time SDK setup (macOS, no Android Studio):

```bash
brew install --cask android-commandlinetools
brew install openjdk@17
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
```

Persist in `~/.zshrc`:

```sh
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$PATH"
```

Build:

```bash
flutter build apk --release          # sideload / direct distribution
flutter build appbundle --release    # .aab for the Play Store
```

Signing for release: create a keystore, reference it from
`android/key.properties` + `android/app/build.gradle.kts`, then rebuild. (Debug
builds are auto-signed with the debug key.)

Considerations:
- **JDK 17 is required** — Gradle 9 / AGP reject newer JDKs.
- `compileSdk` is pinned to **36** (an `afterEvaluate` block in
  `android/build.gradle.kts` forces plugins that default to 34 up to 36; it must
  be registered before evaluation to avoid "Cannot run afterEvaluate when
  already evaluated").
- The `.kdbx` intent-filter and SAF document channel are already in
  `MainActivity.kt` / the manifest.

### 9.4 Windows

```bash
flutter build windows --release
# → build/windows/x64/runner/Release/  (dgvault.exe + DLLs)
```

Package with MSIX or an installer (Inno Setup / WiX). Register the `.kdbx` file
association at **install time** (the app reads the launched path from argv).

### 9.5 Linux

```bash
flutter build linux --release
# → build/linux/x64/release/bundle/  (dgvault + lib/ + data/)
```

Package as a `.deb`, AppImage, Flatpak, or Snap. Ship a `.desktop` file with a
`MimeType=application/x-keepass2;` association so file managers launch dgvault
with the path as argv.

### 9.6 Release checklist

1. Bump `version:` in `pubspec.yaml`.
2. `flutter analyze` clean, `flutter test` green.
3. Regenerate icons if the source changed.
4. Build the target(s) above; sign per platform.
5. Smoke-test the **file-association open** and a **save round-trip** on a real
   device/desktop for each platform you ship.
6. Tag the release in git.

---

## 10. Development environment quick reference

- **Flutter SDK:** `/Users/ytcracker/flutter/flutter/bin` (dev machine; 3.44.x).
- **Android:** `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools`,
  **JDK 17** at `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`.
  AVDs: `pixel_api36` (phone), `tablet_api36`.
  Note: `flutter emulators --launch` takes the **AVD name**; `flutter run -d`
  takes the **running device id** (`emulator-5554`) — they differ.
- **iOS/macOS:** Xcode; simulators come with it. Bundle id `com.dgvault.dgvault`.
- **Running:** see `README.md` §Running for exact `flutter run -d …` invocations.

---

## 11. Further reading

- `README.md` — quick start, running, building.
- `docs/ADR-0001-stack-and-architecture.md` — stack + layering rationale.
- `docs/ADR-0002-zero-knowledge-model.md` — the security/threat model.
- `docs/testing-strategy.md` — how the suite is structured.
- `reviews/` — the multi-round adversarial code/security reviews.
