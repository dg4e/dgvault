#!/usr/bin/env bash
# Register dgvault with LaunchServices, make it the default .kdbx handler, and
# refresh Finder so the new document icon shows. Pass the .app path (defaults to
# the built Release app). For the default to "stick", the app should live in a
# stable location — ideally /Applications/dgvault.app.
set -euo pipefail

APP="${1:-build/macos/Build/Products/Release/dgvault.app}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
UTI="org.keepass.kdbx"
BUNDLE_ID="com.dgvault.dgvault"

[ -d "$APP" ] || { echo "not found: $APP (build it first: flutter build macos)"; exit 1; }

# 1) Tell LaunchServices this app exists and what it can open.
"$LSREGISTER" -f "$APP"

# 2) Make dgvault the default handler for the KeePass UTI.
if command -v duti >/dev/null 2>&1; then
  duti -s "$BUNDLE_ID" "$UTI" all
  echo "set dgvault as default for $UTI via duti."
else
  echo "note: 'duti' not installed (brew install duti) — set the default by hand:"
  echo "  Finder → a .kdbx → Get Info → Open with → dgvault → Change All…"
fi

# 3) Nuke the icon cache so Finder redraws .kdbx files with the new icon.
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
killall Finder Dock 2>/dev/null || true
echo "done — .kdbx files should now show the dgvault document icon."
