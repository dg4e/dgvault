# dgvault Privacy Policy

_Last updated: July 25, 2026_

dgvault is a zero-knowledge, KeePass-compatible password manager. This policy
covers the dgvault apps for iOS, Android, and desktop.

## The short version

We collect nothing. Your data never leaves your device unless you explicitly
sync it somewhere, and even then it is encrypted before it leaves.

## What data dgvault handles

- **Your vault** (passwords, notes, attachments) is stored in a KeePass
  `.kdbx` file on your device, encrypted with keys derived from your master
  password (Argon2 + AES/ChaCha20). We cannot read it. There is no account,
  no server-side copy, and no recovery mechanism — that is the point.
- **Biometric unlock** (Face ID / Touch ID / fingerprint) is handled entirely
  by your operating system. dgvault never sees biometric data; it only
  receives a yes/no from the OS.
- **Sync**, if you enable it, transfers your already-encrypted vault file to
  a destination you choose (e.g. your own WebDAV server). dgvault has no
  sync service of its own and the destination provider's privacy policy
  applies to the encrypted blob they store.

## What we collect

Nothing. dgvault has no analytics, no telemetry, no crash reporting, no ads,
no third-party SDKs that phone home, and no accounts. The app makes no
network connections except the sync destinations you configure yourself and
links you explicitly tap (which open in your browser).

## Data sharing and sale

We hold no data about you, so there is nothing to share or sell.

## Children

dgvault does not collect data from anyone, including children.

## Changes

Changes to this policy will be published at this URL and noted in the app's
release notes.

## Contact

Questions: open an issue at the dgvault repository, or email the address
listed on the app's About screen.
