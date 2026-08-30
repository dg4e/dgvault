# Store listing copy

Reused across App Store Connect and Play Console. Character limits noted.

## App Store Connect

**Name** (30)
```
dgvault
```

**Subtitle** (30)
```
zero-knowledge password vault
```

**Promotional text** (170, changeable anytime without review)
```
yet another boring password vault, encrypted on your device. keepass-backed.
no account, no cloud, no nag-screens. open source. free. i like computers.
hack the planet.
```

**Keywords** (100, comma-separated, no need to repeat the app name)
```
keepass,kdbx,password,manager,vault,offline,totp,2fa,authenticator,encrypted,local,private
```

**Description** (4000)
```
dgvault is a keepass-compatible password manager. your vault is a normal
.kdbx file encrypted on your device. there is no account and no server. we
never see your data.

since it's the standard keepass format, your vault also opens in any other
compatible application.

features:

- totp (2fa): shows the live rotating 6-digit code with a countdown, not just the stored secret
- password generator: random charset or memorable passphrase, with a live entropy readout
- password audit: finds weak, reused, similar, empty, and old passwords
- folders, search, custom sorting; mark any folder "exclude from search"
- entry history, so every save keeps old versions you can restore
- recycle bin
- configurable auto-lock on idle and when the app goes to background
- vault contents hidden from the app switcher
- open vaults from the files app
- super sick about screen
- chungus

crypto notes: vetted primitives only (argon2, aes-256, chacha20), nothing
hand-rolled. biometric unlock happens in the os, the app just gets a yes or
no.

dgvault requires zero network garbage.

open source under apache 2.0: https://github.com/dg4e/dgvault

digital gangster for eternity. rip to the fallen homies. momino is beautiful
and amazing.

written by ytcracker and clord. (c)2026 digital gangster enterprises, llc
```

**Support URL**: https://github.com/dg4e/dgvault/issues
**Marketing URL** (optional): https://github.com/dg4e/dgvault
**Privacy Policy URL**: https://dg4e.github.io/dgvault/privacy-policy.html
**Copyright**: 2026 digital gangster enterprises, llc

**What's New** (0.8.5)
```
you can change your vault's master password now — vault settings › master
password › change password. the vault is re-encrypted under the new password
and saved on the spot.

local backups are fixed too: they were piling up one per save and never
getting cleaned out. vault settings › backups now controls how many to keep
and how long.
```

**What's New** (0.8.4)
```
totp entries now show the live rotating 6-digit code with a countdown, not
just the stored secret. the password generator can make memorable passphrases
too, and there's a new password audit that flags weak, reused, and old logins.
```

**What's New** (0.8.3)
```
search skips your backup and recycle bin folders now, so old archived copies
stop cluttering results. mark any folder "exclude from search" from its menu;
you can still open it and search inside.
```

**What's New** (0.8.2, first release)
```
initial release. hack the planet.
```

## Play Console

**App name** (30): `dgvault`

**Short description** (80)
```
keepass password manager. offline, encrypted, zero-knowledge. no account.
```

**Full description** (4000): same as the App Store description above.

**Contact email**: support@digitalgangster.com
