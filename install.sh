#!/usr/bin/env bash
# Local dev loop only -- a real user runs `omarchy plugin add <repo-url>
# --enable`, which does a plain `git clone` of this whole repo into the
# destination below. This mirrors that shape via copy instead of clone, so
# edits here don't need a push+reclone cycle to test.
#
# Omarchy's plugin loader rejects symlinks inside a plugin folder (including
# the folder itself being one), so the copy is real, not a symlink to this
# checkout -- must re-run after editing anything.
#
# bin/media-pip is copied in too (not left to be found on $PATH), so a real
# `plugin add` clone -- which never runs this script or anything else that
# could symlink the CLI onto $PATH, since there's no post-install hook in
# the manifest schema -- has a source to copy from: Service.qml self-stages
# its own copy of bin/media-pip to ~/.local/state/media-pip/ at shell
# start (see cliPath's comment in Service.qml for why -- a CLI invoked
# from inside the plugin's own install directory doesn't launch). The
# extra symlink onto $PATH below is purely a convenience for testing
# `media-pip <command>` directly from a terminal on this dev machine; the
# plugin itself doesn't depend on it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/io.github.haydenmckay.media-pip"

mkdir -p "$DEST/bin"
cp "$SCRIPT_DIR"/*.json "$SCRIPT_DIR"/*.qml "$DEST"/
cp "$SCRIPT_DIR/bin/media-pip" "$DEST/bin/media-pip"
chmod +x "$DEST/bin/media-pip"
ln -sf "$SCRIPT_DIR/bin/media-pip" "$HOME/.local/bin/media-pip"

omarchy plugin validate "$DEST"
echo "Installed. Run 'omarchy plugin enable io.github.haydenmckay.media-pip' if not already enabled."
