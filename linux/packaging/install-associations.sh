#!/usr/bin/env sh
# Register dgvault as the .kdbx handler on Linux and install the document icon.
# Run per-user (writes under ~/.local) — drop the DESTDIR/prefix in for a
# packaged (deb/rpm/Flatpak) install instead.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

# 1) MIME type: teach the system that *.kdbx is application/x-keepass2.
install -Dm644 "$HERE/dgvault-kdbx.xml" \
  "$DATA/mime/packages/dgvault-kdbx.xml"
update-mime-database "$DATA/mime" || true

# 2) Document icon: one PNG per size into the hicolor theme's mimetypes/.
for size in 16 24 32 48 64 128 256 512; do
  src="$HERE/icons/${size}x${size}/mimetypes/application-x-keepass2.png"
  [ -f "$src" ] && install -Dm644 "$src" \
    "$DATA/icons/hicolor/${size}x${size}/mimetypes/application-x-keepass2.png"
done
gtk-update-icon-cache -f -t "$DATA/icons/hicolor" 2>/dev/null || true

# 3) Desktop entry + make dgvault the DEFAULT handler.
install -Dm644 "$HERE/dgvault.desktop" "$DATA/applications/dgvault.desktop"
update-desktop-database "$DATA/applications" || true
xdg-mime default dgvault.desktop application/x-keepass2

echo "done — .kdbx files now open with dgvault and show its icon."
echo "(log out/in or restart the file manager if the icon doesn't refresh.)"
