#!/usr/bin/env bash
# Omarchy's plugin loader rejects symlinks inside a plugin folder, so the
# live plugin at ~/.config/omarchy/plugins/trigz.media-pip must be a real
# copy of plugin/, not a symlink to it. Re-run this after editing anything
# under plugin/.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/trigz.media-pip"

mkdir -p "$DEST"
cp "$SCRIPT_DIR"/plugin/*.json "$SCRIPT_DIR"/plugin/*.qml "$DEST"/
ln -sf "$SCRIPT_DIR/bin/media-pip" "$HOME/.local/bin/media-pip"

omarchy plugin validate "$DEST"
echo "Installed. Run 'omarchy plugin enable trigz.media-pip' if not already enabled."
