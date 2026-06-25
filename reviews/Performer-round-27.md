# Performer — Round 27 (first real UI — terminal aesthetic)

The presentation layer finally exists. The 26 prior rounds built a complete,
tested engine with zero screens; this round adds `lib/ui/` — a terminal/hacker
design language and a working vertical slice, wired to the real engine (the
unlock genuinely decrypts a KDBX).

## Design system — `lib/ui/theme` + `lib/ui/widgets`
A modernized hacker-terminal language (not a Matrix parody): deep blue-black
surfaces, monospace type (platform fallback stack, no bundled font), a mint-green
primary with cyan/amber/red accents, thin box-drawing borders + corner brackets.
Reusable chrome: `TerminalPanel` (titled, bracketed), `PromptField` (sigil +
borderless input), `TermButton` (`[ LABEL ]` with focus glow), `StatusBar`
(vim/tmux split), `BlinkingCursor`, `TagChip`. `kWideBreakpoint` (760px) drives
responsive layout.

## Vertical slice — `lib/ui/screens` + `lib/ui/state`
- **Unlock** — figlet `dgvault` banner + boot log + PIN prompt. Wired for real:
  `VaultController` seeds a demo DB, encrypts it to KDBX bytes in memory, wraps the
  master password under the PIN in a `KeyVault`. A correct PIN runs `PinUnlock` →
  unwraps the password → `KdbxCodec.read` → the decrypted `Database`. Wrong PIN
  drives `AppLockPolicy` (attempts countdown, lock-out, RESET).
- **Vault** — responsive master/detail: two-pane on desktop/tablet, stacked with
  push-navigation on phones. Live search via the real `EntrySearch` engine.
- **Entry detail** — fields with per-field reveal + copy (clipboard flash), tags,
  metadata; secrets masked by default.
- **Generator** — bottom sheet over the real `PasswordGenerator` with a live
  entropy meter + class toggles.

## Verification
- `vault_controller_test.dart` — real unlock flow: bootstrap → wrong PIN denied +
  budget decremented → correct PIN unlocks + decrypts + `EntrySearch` filters +
  lock drops the DB.
- `widget_test.dart` — locked shows the prompt; unlocked renders seeded entries +
  `UNLOCKED` status.
- **Screenshot-verified on macOS** (`flutter build macos` → run): unlock banner +
  boot log, and the two-pane vault (list with dim usernames/magenta tags + detail
  with reveal/copy).

Fixes this round from a visual review: the hand-written ASCII banner was garbled
(replaced with a correct figlet render); the macOS window now opens at a
comfortable default size with a sane minimum.

`flutter test`: **486 passing / 0 failing.** `flutter analyze`: **0 issues.**

## What the UI still needs (breadth)
Entry create/edit, persistence to a real `.kdbx` (file picker + autosave), the
group tree / folders, settings (PIN/biometric enrolment screens), TOTP live codes,
icons, and per-platform chrome polish (the slice was verified on macOS). The
engine for almost all of this already exists and is tested — this round proved the
wiring pattern; the rest is screens.
