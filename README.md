# dgvault

A cross-platform, KeePass-compatible (**KDBX 3/4**) password manager built in
Flutter, with a hacker/terminal aesthetic that scales from phones to desktops.
Zero-knowledge: your vault is encrypted locally with vetted crypto
(Argon2 / AES-256 / ChaCha20); dgvault never phones home.

```
   _|  _ \ \   / _` |  |  | | __|
  / _` (   |\ V / (   |  |  | |\__ \
\__,_|\___/  \_/ \__,_| \__,_|_|___/   secure vault · kdbx4 · zero-knowledge
```

Runs on **macOS, Windows, Linux, iOS, and Android** from a single codebase.

## Features

- Open/create real `.kdbx` files (KDBX 3 read, KDBX 4 read/write) — interops with KeePass / KeePassXC.
- Folders with add / rename / delete / **drag-to-reorder** / move-to.
- Entries with editing, history (view + restore), delete → Recycle Bin, **drag-to-reorder**, move-to, sort.
- Password generator (charset + diceware), TOTP, password audit.
- Resizable panes (desktop); responsive two-pane / stacked layouts.
- Settings: KDF transform rounds with a **Benchmark** button, history limits, recycle bin toggle.
- Native desktop window title shows `dgvault vX.Y.Z — <file>`; an Amiga-style **About** cracktro.

## Requirements

- **Flutter SDK** (stable). This repo was developed against Flutter 3.44.x.
- Per target:
  - **macOS / iOS**: Xcode + CocoaPods.
  - **Android**: Android SDK (cmdline-tools, platform-tools, **platform 36**, **build-tools 36.0.0**) and a **JDK 17** (Gradle 9 / AGP reject newer JDKs).
  - **Windows / Linux**: the standard Flutter desktop toolchain (Visual Studio / clang+GTK).

`flutter doctor` should be green for the targets you want.

## Running

Install dependencies once: `flutter pub get`.

### Desktop

```bash
flutter run -d macos      # or: -d windows / -d linux
```

### iOS Simulator (iPhone / iPad)

Xcode ships the simulators; no extra install.

```bash
open -a Simulator                                 # boot the default simulator
flutter run -d "iPhone 15 Pro"

# For a specific device (e.g. iPad), boot it first:
xcrun simctl boot "iPad Pro 13-inch (M4)"
open -a Simulator
flutter run -d "iPad Pro 13-inch (M4)"
```

`flutter devices` lists exact names/ids. In the run session: `r` hot reload, `R` hot restart, `q` quit.

### Android emulator (phone / tablet)

One-time emulator + image + AVD setup (the SDK install is separate, see below):

```bash
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools   # your SDK path
sdkmanager "emulator" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n pixel_api36  -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7
avdmanager create avd -n tablet_api36 -k "system-images;android-36;google_apis;arm64-v8a" -d "Nexus 10"
```

Launch + run:

```bash
flutter emulators                       # lists pixel_api36 / tablet_api36
flutter emulators --launch pixel_api36
flutter run -d pixel_api36              # or -d tablet_api36
```

### Physical devices

- **iOS**: trust the Mac, select the device, `flutter run` (needs a signing team in Xcode for a real device).
- **Android**: enable Developer Options → USB debugging, plug in, `flutter run`.

### First-time Android SDK setup (macOS, no Android Studio)

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

## Building releases

```bash
flutter build macos
flutter build apk --release            # or: appbundle for Play Store
flutter build ios --release            # needs signing
flutter build windows                  # / linux
```

## Testing & quality

```bash
flutter test       # full unit + widget suite
flutter analyze    # static analysis (should report no issues)
```

## App icon

The icon (a vault dial with the `dg` wordmark) is generated for every platform
from one source:

```bash
python3 tool/gen_icon.py     # writes macOS/iOS/Android/Windows/Linux icons
```

## Architecture

Layered so the security core stays pure and testable headless:

- `lib/core/` — platform-agnostic Dart: KDBX format, crypto, model, generators, search, diff/merge.
- `lib/data/` — `dart:io`-backed: repositories, sync, import/export, compression.
- `lib/platform/` — device adapters (secure storage, biometrics, WebDAV sync).
- `lib/ui/` — Flutter UI (terminal theme, screens, widgets).

See `docs/ADR-0001-stack-and-architecture.md` and
`docs/ADR-0002-zero-knowledge-model.md` for the rationale.

## Security

Zero-knowledge, local-first. No telemetry. Crypto uses vetted primitives
(pointycastle / cryptography) — no hand-rolled crypto. Untrusted file parsers
are bounds-checked; sync credentials are never sent over plaintext HTTP. See the
audits in `reviews/`.
