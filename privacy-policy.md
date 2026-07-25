# dgvault Privacy Policy

Last updated: July 25, 2026

dgvault is a zero-knowledge, KeePass-compatible password manager. This policy
covers the dgvault apps for iOS, Android, and desktop.

## What we collect

Nothing. dgvault has no accounts, no servers, no analytics, no telemetry, no
crash reporting, no ads, and no third-party SDKs that phone home.

## Where your data lives

Your vault is a standard KeePass `.kdbx` file stored on your device, encrypted
with keys derived from your master password (Argon2, AES, ChaCha20). We never
see your master password or anything inside your vault. There is no cloud
copy and no recovery backdoor. If you lose your master password, nobody can
recover your data, including us. That is the point.

Biometric unlock (Face ID, Touch ID, fingerprint) is handled entirely by your
operating system. The app only gets a yes or no back. It never sees
biometric data.

If you set up sync, your already-encrypted vault file is sent to a
destination you pick, such as your own WebDAV server. dgvault runs no sync
service of its own. Whatever provider you choose stores an encrypted blob it
cannot read, under its own privacy policy.

The only network connections the app makes are the sync destinations you
configure yourself and links you tap, which open in your browser.

## Sharing and selling

We hold nothing about you, so there is nothing to share or sell.

## Children

Same answer: no data is collected from anyone, kids included.

## Changes

Updates to this policy are published at this URL and noted in the app's
release notes.

## Contact

Open an issue on the dgvault repository, or email the address on the app's
About screen.
