# Release & store submission

Privacy policy URL (both store consoles):
<https://dg4e.github.io/dgvault/privacy-policy.html>
(GitHub Pages, published from `docs/` on master.)

Targets for store distribution: **iOS (App Store)** and **Android (Google Play)**.
macOS desktop is intentionally not App-Store-distributed; Windows/Linux/web are
handled separately (not covered here yet).

Version comes from `pubspec.yaml` (`version: X.Y.Z` → build name; append
`+N` for the build number, e.g. `0.8.2+3`). Bump the `+N` for every store upload.

## Android (Google Play)

### One-time setup

1. Generate the upload keystore (do this once and back it up somewhere safe;
   losing it is recoverable only because Play App Signing holds the real key):

   ```sh
   keytool -genkey -v \
     -keystore ~/keystores/dgvault-upload.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```

2. Create `android/key.properties` (gitignored):

   ```properties
   storePassword=<keystore password>
   keyPassword=<key password>
   keyAlias=upload
   storeFile=/Users/ytcracker/keystores/dgvault-upload.jks
   ```

   `android/app/build.gradle.kts` picks this up automatically; without it,
   release builds fall back to debug signing so `flutter run --release`
   still works on a fresh checkout.

3. In Play Console: create the app, opt into **Play App Signing**, and
   register the upload key on first upload.

### Every release

```sh
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

Upload the `.aab` in Play Console. First submission also requires:

- **Data safety form**: dgvault is zero-knowledge: no data collected, no
  data shared, all vault data encrypted locally.
- **Content rating** questionnaire.
- Privacy policy URL (required even with no data collection).
- Store listing: icon 512×512, feature graphic 1024×500, phone screenshots
  (min 2), 7-inch/10-inch tablet screenshots if targeting tablets.
- New personal developer accounts must run a **closed test with ~12 testers
  for 14 days** before production access is granted.

## iOS (App Store)

### One-time setup

1. In [App Store Connect](https://appstoreconnect.apple.com): Certificates →
   the bundle ID `com.dgvault.dgvault` is registered automatically by Xcode,
   then create the app record (Apps → +).
2. In Xcode (`open ios/Runner.xcworkspace`): select the Runner target →
   Signing & Capabilities → set your Team, keep "Automatically manage
   signing" on.

### Every release

```sh
flutter build ipa --release
# → build/ios/ipa/dgvault.ipa
```

Upload with the Transporter app, or via Xcode Organizer
(`open build/ios/archive/Runner.xcarchive`).

First submission also requires:

- App Privacy "nutrition label": same zero-knowledge answers as Play.
- Privacy policy URL.
- Screenshots: 6.9-inch iPhone (mandatory), 13-inch iPad if iPad is enabled.
- Export compliance: `ITSAppUsesNonExemptEncryption=false` is already set in
  `Info.plist` (standard crypto protecting the user's own data is exempt),
  so no per-build questionnaire appears.

## Store screenshots

Ready-to-upload screenshots live in `store/screenshots/` (iPhone 6.9",
iPad 13", Android phone, Android 10" tablet). To regenerate: build with
`--dart-define=DGVAULT_DEMO=vault|locked|detail|generator` (seeds a demo
vault and stages that screen, see `lib/ui/dev/demo_vault.dart`), or
`DGVAULT_OPEN_ABOUT=true` for the cracktro, then capture:

- iOS: `xcrun simctl io <udid> screenshot out.png`
- Android: `adb -s <dev> emu screenrecord screenshot <dir>`, plain
  `adb screencap` returns black because the app sets FLAG_SECURE
  (intentional; the emulator framebuffer capture bypasses it).

## Export-compliance paperwork (annual, US)

The app uses standard encryption (AES, ChaCha20, Argon2), which is exempt
from App Store per-build reporting, but a **self-classification report** must
be emailed to US BIS/NSA once a year (by Feb 1) covering mass-market crypto:
<https://www.bis.doc.gov/index.php/policy-guidance/encryption/4-reports-and-reviews/a-annual-self-classification>

## Licensing note

dgvault is GPL-3.0. The copyright holder can publish to the App Store freely
(the license binds licensees, not the author). If outside contributions are
ever accepted, contributors must grant an App Store distribution exception
(or sign a CLA), because stock GPL-3 terms conflict with Apple's.
